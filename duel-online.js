/* duel-online.js — petite couche d'accès à Supabase, partagée par le jeu (hôte) et parier.html (amis).
   Nécessite : supabase-js (CDN) + config.js (window.DUEL_CONFIG). Si ce n'est pas configuré, window.DuelOnline vaut null
   et le jeu fonctionne en mode local comme avant. */
(function(){
  const cfg = window.DUEL_CONFIG || {};
  if(!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY || !window.supabase || /xxxx|VOTRE/i.test(cfg.SUPABASE_URL)){ window.DuelOnline = null; return; }
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  const DOMAIN = cfg.EMAIL_DOMAIN || 'duelroyale.app';
  const slug = s => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const emailOf = pseudo => slug(pseudo) + '@' + DOMAIN;
  const fail = e => { throw new Error((e && e.message) ? e.message : String(e)); };
  async function rpc(name, args){ const { data, error } = await sb.rpc(name, args || {}); if(error) fail(error); return data; }
  async function rows(q){ const { data, error } = await q; if(error) fail(error); return data || []; }

  window.DuelOnline = {
    slug,
    async signUp(pseudo, code){
      pseudo = String(pseudo || '').trim();
      if(pseudo.length < 2 || pseudo.length > 20 || slug(pseudo).length < 2) throw new Error('Pseudo : 2 à 20 caractères (lettres ou chiffres).');
      if(String(code || '').length < 6) throw new Error('Code secret : 6 caractères minimum.');
      const { data, error } = await sb.auth.signUp({ email: emailOf(pseudo), password: code, options: { data: { pseudo } } });
      if(error){
        const m = error.message || '';
        if(/already registered|already been registered/i.test(m)) throw new Error('Ce pseudo est déjà pris.');
        if(/database error/i.test(m)) throw new Error('Pseudo déjà pris ou invalide.');
        if(/email.*(invalid|not allowed)|invalid.*email/i.test(m)) throw new Error('Supabase refuse le domaine e-mail interne : change EMAIL_DOMAIN dans config.js.');
        throw new Error(m);
      }
      if(!data.session) throw new Error('Supabase demande une confirmation par e-mail : désactive « Confirm email » (Authentication → Providers → Email).');
    },
    async signIn(pseudo, code){
      const { error } = await sb.auth.signInWithPassword({ email: emailOf(String(pseudo || '').trim()), password: code });
      if(error) throw new Error('Pseudo ou code incorrect.');
    },
    signOut(){ return sb.auth.signOut(); },
    async me(){
      const { data: { session } } = await sb.auth.getSession();
      if(!session) return null;
      const { data, error } = await sb.from('players').select('id,pseudo,balance,is_host,last_rescue').eq('id', session.user.id).single();
      return error ? null : data;
    },
    async activeRound(){ const r = await rows(sb.from('rounds').select('*').in('status', ['open', 'locked']).order('id', { ascending: false }).limit(1)); return r[0] || null; },
    async lastClosedRound(){ const r = await rows(sb.from('rounds').select('*').in('status', ['finished', 'cancelled']).order('id', { ascending: false }).limit(1)); return r[0] || null; },
    bets(roundId){ return rows(sb.from('bets').select('id,player_id,monster_id,amount,odd,payout,players(pseudo)').eq('round_id', roundId).order('id', { ascending: true })); },
    myBets(playerId){ return rows(sb.from('bets').select('id,round_id,monster_id,amount,odd,payout,rounds(status,winner_id,monsters)').eq('player_id', playerId).order('id', { ascending: false }).limit(8)); },
    leaderboard(){ return rows(sb.from('players').select('pseudo,balance').order('balance', { ascending: false }).limit(20)); },
    openRound(monsters){ return rpc('open_round', { p_monsters: monsters }); },
    lockRound(id){ return rpc('lock_round', { p_round: id }); },
    finishRound(id, winner){ return rpc('finish_round', { p_round: id, p_winner: winner === undefined ? null : winner }); },
    cancelRound(id){ return rpc('cancel_round', { p_round: id }); },
    placeBet(round, monster, amount){ return rpc('place_bet', { p_round: round, p_monster: String(monster), p_amount: Math.floor(amount) }); },
    cancelBet(round){ return rpc('cancel_bet', { p_round: round }); },
    claimRescue(){ return rpc('claim_rescue'); }
  };
})();
