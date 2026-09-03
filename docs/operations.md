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
- appeler l'Edge Function sans secret (401 attendu) ;
- envoyer un payload de test avec un identifiant d'idempotence neuf,
  puis le répéter (statut `duplicate`, compteur inchangé) ;
- vérifier qu'aucun compteur public ne change avant 10 contributions nouvelles,
  puis que le lot complet apparaît en une seule fois ;
- inspecter les logs Edge pour confirmer qu'aucun payload n'est journalisé.

La collecte réelle est activée. Le secret serveur, les reçus d'idempotence et la
limite de cinq contributions par empreinte réseau et par jour constituent la
première barrière anti-abus. Ajouter ensuite Turnstile avec validation côté
serveur avant toute campagne de trafic importante ; ne jamais utiliser ses clés
de test en production. Le réglage `anonymous_aggregate_submissions_enabled`
reste le coupe-circuit immédiat.

`supabase/config.toml` contient des URL locales et ne doit donc pas être poussé
tel quel en production. Avant le futur dashboard, configurez dans Supabase Auth
les URL exactes du site et désactivez les inscriptions publiques.

## Publication d'une nouvelle version du quiz

1. Appeler `clone_quiz_version(source, cible, libellé)`. La cible doit respecter
   le format `YYYY-MM-DD-vN` et est créée en `draft`.
2. Modifier les questions, positions et liens du brouillon avec la session
   Supabase du membre du staff.
3. Relire puis passer les questions et positions retenues à `published`.
4. Vérifier le snapshot `collected` vide généré et ses compteurs à zéro, ou un
   import réel explicitement documenté.
5. Appeler `publish_quiz_version(cible, snapshot)`. La RPC admin publie le
   snapshot, archive l'ancienne version courante et publie la cible dans une
   transaction unique.

Les triggers bloquent les mutations des entrées de score d'une version déjà
publiée, les créations directes en état `published` et les versions courantes
rattachées à une campagne non publiée. Les éditeurs peuvent retirer les
relations d'un brouillon, mais aucune relation d'une version publiée.

## Accès du backoffice

- authentifier la personne avec Supabase Auth email/mot de passe ;
- appeler `get_my_staff_profile()` et refuser l'accès en l'absence de ligne ;
- utiliser le JWT de cette même session pour toutes les écritures afin que
  l'audit conserve l'acteur ;
- réserver `list_editorial_audit_events()` aux écrans admin ;
- gérer les invitations et rôles staff hors du navigateur, via le Dashboard ou
  une future route serveur protégée utilisant l'API Auth admin.

La clé `service_role` ne doit jamais être placée dans le backoffice. Une surface
de gestion globale des comptes n'est volontairement pas exposée par la base :
le profil courant suffit pour l'autorisation de ce lot et minimise les données
Auth accessibles.

## Rotation et incidents

- faire tourner immédiatement tout secret copié dans un canal non sûr ;
- faire tourner séparément le mot de passe DB, le secret serveur→Edge et la clé
  HMAC ;
- une rotation de clé HMAC invalide seulement les anciens reçus
  d'idempotence, pas les agrégats ;
- désactiver rapidement la collecte avec le réglage
  `anonymous_aggregate_submissions_enabled` ;
- ne jamais exposer la `service_role` au navigateur.
