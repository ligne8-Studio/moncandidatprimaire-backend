# Sécurité et confidentialité

Les réponses au quiz peuvent révéler des opinions politiques. Elles sont donc
traitées comme des données particulièrement sensibles et ne sont pas persistées.

## Flux de contribution

1. L'utilisateur termine son quiz localement.
2. Une contribution au classement exige un consentement séparé et explicite.
3. Le navigateur envoie les réponses au serveur Next.js du même site.
4. Next.js authentifie son appel vers l'Edge Function avec un secret serveur.
5. L'Edge Function relit la version publiée, recalcule tous les scores et
   détermine le premier candidat sans faire confiance au score du navigateur.
6. Une transaction atomique incrémente un compteur.
7. Les compteurs temps réel restent invisibles au public. Le snapshot agrégé est
   relâché automatiquement par cohortes de 10 contributions.
8. Le corps de requête est abandonné ; aucune réponse individuelle n'est
   écrite en base ou dans les logs.

L'agrégation est irréversible : il n'est pas possible de retirer ultérieurement
une contribution individuelle qui n'existe plus en tant que ligne.

## Minimisation

- aucune table `quiz_answers`, `user_scores` ou `user_matches` ;
- aucun lien avec Supabase Auth ou Vercel Analytics ;
- aucun stockage d'IP ou de user-agent ;
- HMAC quotidien d'adresse réseau pour le rate-limit, supprimé sous 72 h ;
- HMAC d'idempotence supprimé après 30 jours ;
- réponse HTTP sans cache ;
- corps limité à 16 KiB ;
- cinq contributions maximum par empreinte réseau et par jour ;
- aucun corps de requête dans les logs applicatifs.
- aucun delta de compteur réel exposé publiquement ; les classements utilisent
  des snapshots relâchés par lots.

Faire relire le texte de consentement et la durée de conservation par un conseil
juridique/DPO. Avant une campagne de trafic importante, ajouter Turnstile et
valider chaque jeton côté serveur. Une clé publique Supabase et CORS ne
constituent pas une protection anti-abus ; les protections actives sont le
secret serveur, l'idempotence et la limite quotidienne par empreinte réseau.

## Autorisations

- `anon` : lecture des seuls contenus publiés et agrégats ;
- `authenticated` sans rôle staff : même lecture publique ;
- `editor` : lecture et préparation des brouillons ;
- `admin` : publication, réglages opérationnels, classements et suppression ;
- `service_role` : RPC d'agrégation et tâches internes seulement côté serveur.

Les rôles sont dans `private.staff_members`, jamais dans `user_metadata`. Une
désactivation y prend effet immédiatement. Toutes les tables publiques ont RLS
et des grants explicites ; toutes les fonctions sont privées par défaut.

Le journal d'audit attribue les mutations effectuées avec le JWT du staff. Les
écritures techniques via migration, Dashboard SQL ou `service_role` n'ont pas
de `auth.uid()` et doivent être suivies dans le processus d'exploitation.
