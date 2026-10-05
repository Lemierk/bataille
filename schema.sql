-- =====================================================================
--  DUEL ROYALE EN LIGNE — schéma Supabase (à coller dans SQL Editor puis "Run")
--  Les clients ne modifient JAMAIS les soldes directement : tout passe par
--  des fonctions (RPC) qui vérifient les règles. Jetons virtuels uniquement.
-- =====================================================================

-- ---------- Tables ----------
create table if not exists public.players (
  id          uuid primary key references auth.users(id) on delete cascade,
  pseudo      text not null check (char_length(pseudo) between 2 and 20),
  balance     integer not null default 1000 check (balance >= 0),
  is_host     boolean not null default false,
  last_rescue timestamptz,
  created_at  timestamptz not null default now()
);
create unique index if not exists players_pseudo_key on public.players (lower(pseudo));

create table if not exists public.rounds (
  id          bigint generated always as identity primary key,
  status      text not null default 'open' check (status in ('open','locked','finished','cancelled')),
  monsters    jsonb not null,            -- [{id,name,odd,p,img,type}, ...] : cotes FIGÉES à l'ouverture
  winner_id   text,
  host_id     uuid references public.players(id),
  created_at  timestamptz not null default now(),
  locked_at   timestamptz,
  finished_at timestamptz
);
-- une seule manche active (ouverte ou verrouillée) à la fois
create unique index if not exists one_active_round on public.rounds ((true)) where status in ('open','locked');

create table if not exists public.bets (
  id         bigint generated always as identity primary key,
  round_id   bigint not null references public.rounds(id) on delete cascade,
  player_id  uuid   not null references public.players(id) on delete cascade,
  monster_id text   not null,
  amount     integer not null check (amount > 0),
  odd        numeric(6,1) not null,
  payout     integer,                    -- null tant que la manche n'est pas terminée
  created_at timestamptz not null default now(),
  unique (round_id, player_id)           -- un seul pari par joueur et par manche
);

-- ---------- Création automatique du joueur à l'inscription ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.players (id, pseudo)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'pseudo'), ''), split_part(new.email, '@', 1)));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Sécurité : lecture seule pour les clients ----------
alter table public.players enable row level security;
alter table public.rounds  enable row level security;
alter table public.bets    enable row level security;
drop policy if exists "players_lecture" on public.players;
drop policy if exists "rounds_lecture"  on public.rounds;
drop policy if exists "bets_lecture"    on public.bets;
create policy "players_lecture" on public.players for select to authenticated using (true);
create policy "rounds_lecture"  on public.rounds  for select to authenticated using (true);
create policy "bets_lecture"    on public.bets    for select to authenticated using (true);
revoke insert, update, delete on public.players, public.rounds, public.bets from anon, authenticated;

-- ---------- Fonctions ----------
create or replace function public._require_host() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.players where id = auth.uid() and is_host) then
    raise exception 'Réservé à l''hôte';
  end if;
end $$;

-- Hôte : ouvre les mises (cotes fixées ici)
create or replace function public.open_round(p_monsters jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public._require_host();
  if jsonb_typeof(p_monsters) <> 'array' or jsonb_array_length(p_monsters) < 2 then
    raise exception 'Liste de monstres invalide';
  end if;
  begin
    insert into public.rounds (monsters, host_id) values (p_monsters, auth.uid()) returning id into v_id;
  exception when unique_violation then
    raise exception 'Une manche est déjà en cours : termine-la ou annule-la d''abord';
  end;
  return v_id;
end $$;

-- Hôte : verrouille les mises (juste avant le début de la bataille)
create or replace function public.lock_round(p_round bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_host();
  update public.rounds set status = 'locked', locked_at = now() where id = p_round and status = 'open';
  if not found then raise exception 'Cette manche n''est pas ouverte'; end if;
end $$;

-- Joueur : parier (le montant est retiré tout de suite ; remplace un pari précédent de la même manche)
create or replace function public.place_bet(p_round bigint, p_monster text, p_amount integer) returns void
language plpgsql security definer set search_path = public as $$
declare v_round public.rounds; v_odd numeric; v_bal integer; v_old public.bets;
begin
  if auth.uid() is null then raise exception 'Connecte-toi d''abord'; end if;
  select * into v_round from public.rounds where id = p_round for share;
  if not found or v_round.status <> 'open' then raise exception 'Les mises sont fermées'; end if;
  select (m->>'odd')::numeric into v_odd from jsonb_array_elements(v_round.monsters) m where m->>'id' = p_monster;
  if v_odd is null then raise exception 'Monstre inconnu'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Mise invalide'; end if;
  select balance into v_bal from public.players where id = auth.uid() for update;
  select * into v_old from public.bets where round_id = p_round and player_id = auth.uid();
  if found then
    v_bal := v_bal + v_old.amount;
    delete from public.bets where id = v_old.id;
  end if;
  if p_amount > v_bal then raise exception 'Solde insuffisant'; end if;
  update public.players set balance = v_bal - p_amount where id = auth.uid();
  insert into public.bets (round_id, player_id, monster_id, amount, odd)
  values (p_round, auth.uid(), p_monster, p_amount, v_odd);
end $$;

-- Joueur : retirer son pari tant que les mises sont ouvertes
create or replace function public.cancel_bet(p_round bigint) returns void
language plpgsql security definer set search_path = public as $$
declare v_old public.bets;
begin
  if auth.uid() is null then raise exception 'Connecte-toi d''abord'; end if;
  perform 1 from public.rounds where id = p_round and status = 'open' for share;
  if not found then raise exception 'Les mises sont fermées'; end if;
  select * into v_old from public.bets where round_id = p_round and player_id = auth.uid() for update;
  if not found then return; end if;
  delete from public.bets where id = v_old.id;
  update public.players set balance = balance + v_old.amount where id = auth.uid();
end $$;

-- Hôte : clôture la manche. p_winner = id du monstre gagnant, ou NULL en cas de match nul (remboursement)
create or replace function public.finish_round(p_round bigint, p_winner text) returns void
language plpgsql security definer set search_path = public as $$
declare v_round public.rounds;
begin
  perform public._require_host();
  select * into v_round from public.rounds where id = p_round for update;
  if not found or v_round.status <> 'locked' then raise exception 'La manche doit être verrouillée pour être clôturée'; end if;
  if p_winner is not null and not exists (select 1 from jsonb_array_elements(v_round.monsters) m where m->>'id' = p_winner) then
    raise exception 'Gagnant inconnu';
  end if;
  update public.bets b set payout = case
      when p_winner is null then b.amount
      when b.monster_id = p_winner then round(b.amount * b.odd)::integer
      else 0 end
    where b.round_id = p_round;
  update public.players p set balance = p.balance + s.total
    from (select player_id, sum(payout)::integer as total from public.bets where round_id = p_round group by player_id) s
    where s.player_id = p.id;
  update public.rounds set status = 'finished', winner_id = p_winner, finished_at = now() where id = p_round;
end $$;

-- Hôte : annule la manche et rembourse tout le monde
create or replace function public.cancel_round(p_round bigint) returns void
language plpgsql security definer set search_path = public as $$
declare v_round public.rounds;
begin
  perform public._require_host();
  select * into v_round from public.rounds where id = p_round for update;
  if not found or v_round.status not in ('open','locked') then raise exception 'Manche introuvable ou déjà terminée'; end if;
  update public.bets set payout = amount where round_id = p_round;
  update public.players p set balance = p.balance + s.total
    from (select player_id, sum(amount)::integer as total from public.bets where round_id = p_round group by player_id) s
    where s.player_id = p.id;
  update public.rounds set status = 'cancelled', finished_at = now() where id = p_round;
end $$;

-- Joueur : dépannage (+500 jetons si solde < 100, une fois par ~20 h)
create or replace function public.claim_rescue() returns integer
language plpgsql security definer set search_path = public as $$
declare v_p public.players;
begin
  if auth.uid() is null then raise exception 'Connecte-toi d''abord'; end if;
  select * into v_p from public.players where id = auth.uid() for update;
  if v_p.balance >= 100 then raise exception 'Tu as encore assez de jetons'; end if;
  if v_p.last_rescue is not null and v_p.last_rescue > now() - interval '20 hours' then
    raise exception 'Dépannage déjà utilisé récemment';
  end if;
  update public.players set balance = balance + 500, last_rescue = now() where id = auth.uid();
  return v_p.balance + 500;
end $$;

-- Droits d'exécution : réservés aux utilisateurs connectés
revoke all on function public._require_host() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'open_round(jsonb)','lock_round(bigint)','place_bet(bigint,text,integer)','cancel_bet(bigint)',
    'finish_round(bigint,text)','cancel_round(bigint)','claim_rescue()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------- À faire UNE FOIS après ton inscription (remplace TonPseudo) ----------
-- update public.players set is_host = true where lower(pseudo) = lower('TonPseudo');
-- ---------- Remettre tous les soldes à 1000 si besoin ----------
-- update public.players set balance = 1000;
