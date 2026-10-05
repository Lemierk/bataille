# Duel Royale en ligne — installation (≈ 20 min)

**Principe** : tu lances la bataille sur `index.html` (page hôte). Tes amis ouvrent `parier.html` sur leur téléphone, parient avec des jetons virtuels, et Supabase garde les soldes, les mises et les gains.

## Fichiers
| Fichier | Rôle |
|---|---|
| `index.html` | Le jeu (page de l'hôte) + panneau « Mode en ligne » |
| `parier.html` | La page des amis (compte, mises, classement) |
| `duel-online.js` | Liaison avec Supabase (partagée) |
| `config.example.js` | Modèle de configuration → à copier en `config.js` |
| `schema.sql` | Tables et règles à exécuter dans Supabase |

## 1. Supabase
1. Ouvre ton projet → **SQL Editor** → colle tout `schema.sql` → **Run**.
2. **Authentication → Providers → Email** : désactive **« Confirm email »** (sinon les comptes ne se créent pas). Aucun e-mail n'est jamais envoyé : le pseudo est transformé en faux e-mail interne.
3. **Project Settings → API** : copie l'**URL** du projet et la clé **anon / publishable**.

## 2. Configuration
Copie `config.example.js` en **`config.js`**, remplace les deux valeurs. (Cette clé est publique par conception : ce sont les règles du `schema.sql` qui protègent les soldes.)

## 3. Tes images
Mets les PNG de tes monstres (et `blueeyes2.png`) **dans le même dossier** que `index.html`, avec les mêmes noms que dans la liste `MONSTERS`.

## 4. GitHub puis Vercel
1. Crée un dépôt GitHub et envoie-y tous les fichiers (dont `config.js` et tes images).
2. Vercel → **Add New → Project** → importe le dépôt → *Framework Preset* : **Other**, pas de commande de build → **Deploy**.
3. Tu obtiens `https://ton-projet.vercel.app/` (le jeu) et `https://ton-projet.vercel.app/parier.html` (le lien à donner à tes amis).

## 5. Devenir hôte (une seule fois)
1. Ouvre `parier.html` et **crée ton compte** (pseudo + code de 6 caractères minimum).
2. Dans Supabase → SQL Editor :
   ```sql
   update public.players set is_host = true where lower(pseudo) = lower('TonPseudo');
   ```

## 6. Une soirée de paris
1. Sur `index.html`, panneau **Mode en ligne** : connecte-toi avec ton compte hôte.
2. Clique **Nouvelle bataille** (état propre), puis **Ouvrir les mises**. Les cotes sont figées pour la manche.
3. Tes amis (sur `parier.html`) choisissent un monstre et une mise. Ils peuvent modifier ou retirer leur pari tant que c'est ouvert.
4. Clique **Lancer le duel** : les mises se verrouillent, puis la bataille démarre. Partage ton écran (Discord, Teams…) pour que tout le monde regarde.
5. À la fin, le gagnant est envoyé automatiquement : gains versés, classement mis à jour.

Si quelque chose bloque : **Annuler la manche** rembourse tout le monde ; si l'envoi du résultat échoue (réseau), un bouton **Réessayer l'envoi du résultat** apparaît. Ne ferme pas l'onglet de l'hôte pendant la bataille.

## Règles et bon à savoir
- Jetons **virtuels** uniquement (1 000 au départ). Un joueur à moins de 100 jetons peut demander un « dépannage » de +500 (1 fois par ~20 h).
- Un pari par joueur et par manche. Gain = mise × cote si le monstre gagne ; match nul = remboursement.
- Remettre tous les soldes à 1000 : `update public.players set balance = 1000;`
- Si Supabase refuse la création de compte à cause du faux domaine e-mail, change `EMAIL_DOMAIN` dans `config.js`.
- La section « Joueurs / Parier » locale du jeu reste utilisable pour jouer sans internet ; elle est indépendante du mode en ligne.
- Un projet Supabase gratuit peut être mis en pause après une longue inactivité : vérifie les conditions actuelles et relance-le depuis le tableau de bord si besoin.
