// Copie ce fichier en "config.js" et remplis les 2 valeurs (Supabase → Project Settings → API).
// La clé "anon / publishable" est faite pour être publique : la sécurité est assurée par le schéma SQL.
window.DUEL_CONFIG = {
  SUPABASE_URL: "https://xxxxxxxxxxxx.supabase.co",
  SUPABASE_ANON_KEY: "xxxxxxxxxxxxxxxxxxxxxxxx",
  EMAIL_DOMAIN: "duelroyale.app"   // faux domaine interne (aucun e-mail n'est envoyé) ; à changer seulement si Supabase le refuse
};
