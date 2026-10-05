// Copie ce fichier en "config.js" et remplis les 2 valeurs (Supabase → Project Settings → API).
// La clé "anon / publishable" est faite pour être publique : la sécurité est assurée par le schéma SQL.
window.DUEL_CONFIG = {
  SUPABASE_URL: "https://tusqcgkibodnxunopsyn.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR1c3FjZ2tpYm9kbnh1bm9wc3luIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTExODM1OTQsImV4cCI6MjEwNjc1OTU5NH0.nx-Qx5Tlu3q2SkqnQd37o69VO6RemqpQ32RxuYKheh0",
  EMAIL_DOMAIN: "duelroyale.app"   // faux domaine interne (aucun e-mail n'est envoyé) ; à changer seulement si Supabase le refuse
};
