# Exploitation

## Contrôles avant production

```bash
npm ci
npm run content:generate
git diff --exit-code -- supabase/migrations/20260903134700_seed_editorial_content.sql
npm run db:start
npm run db:reset
npm run assets:upload:local
npm run db:lint
npm run db:test
deno fmt --check supabase/functions
deno test supabase/functions/submit-quiz-result
npm run functions:check
```

Faire ensuite un `db push --linked --dry-run`. Ne jamais lancer
`db reset --linked`, qui détruirait les données distantes.

## Après production

- comparer `supabase migration list --linked` avec le dépôt ;
- exécuter les advisors sécurité et performance ;
- régénérer `generated/database.types.ts` depuis le projet lié ;
- vérifier les volumes par SQL et les vues avec la clé publique ;
- charger puis vérifier les portraits avec `npm run assets:upload:linked` ;
- appeler l'Edge Function sans secret (401 attendu), puis avec le secret
  serveur (503 `submissions_disabled` attendu tant que le snapshot est
  synthétique) ;
- après activation sur un snapshot réel, envoyer un payload de test consentant
  avec un identifiant d'idempotence neuf, puis le répéter (statut `duplicate`,
  compteur inchangé) ;
- inspecter les logs Edge pour confirmer qu'aucun payload n'est journalisé.

La collecte reste volontairement désactivée tant que le snapshot courant est
`synthetic`. Son activation exige d'abord un snapshot réel/importé complet, une
couverture éditoriale suffisante pour tous les candidats, un consentement relu
et une protection anti-bot. Ne mélangez jamais des compteurs réels à un socle
de démonstration.

`supabase/config.toml` contient des URL locales et ne doit donc pas être poussé
tel quel en production. Avant le futur dashboard, configurez dans Supabase Auth
les URL exactes du site et désactivez les inscriptions publiques.

## Publication d'une nouvelle version du quiz

1. Créer la version en `draft`.
2. Copier candidats, barème, questions, positions et liens de sources.
3. Appliquer les changements et lancer les tests éditoriaux.
4. Dans une transaction, archiver l'ancienne version courante et publier la
   nouvelle.
5. Créer ses compteurs de classement et son éventuel snapshot initial.

Les triggers bloquent les mutations des entrées de score d'une version déjà
publiée.

## Rotation et incidents

- faire tourner immédiatement tout secret copié dans un canal non sûr ;
- faire tourner séparément le mot de passe DB, le secret serveur→Edge et la clé
  HMAC ;
- une rotation de clé HMAC invalide seulement les anciens reçus
  d'idempotence, pas les agrégats ;
- désactiver rapidement la collecte avec le réglage
  `anonymous_aggregate_submissions_enabled` ;
- ne jamais exposer la `service_role` au navigateur.
