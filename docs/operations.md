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
npm run functions:test
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

## Publication d'un contexte explicatif

Une correction pédagogique ne doit pas cloner le quiz : cela fragmenterait à
tort les agrégats communautaires alors que les entrées de score n'ont pas
changé.

1. Appeler `save_question_context_draft(question_id, body, last_reviewed_at)`
   avec la session d'un éditeur ou admin. Le texte nettoyé doit contenir entre
   1 et 240 caractères et la date de revue ne peut pas être future.
2. Relire l'unique brouillon visible par le staff.
3. Appeler `publish_question_context_revision(question_id)` avec une session
   admin. La nouvelle révision devient immédiatement le contexte effectif de
   `api_questions` ; les publications antérieures restent immuables.

Ces deux RPC publiques sont `security invoker`. Leurs implémentations
`security definer` restent dans le schéma `private`, vérifient le rôle staff et
écrivent dans le journal d'audit avec le JWT de la session.
L'historique des révisions n'est jamais exposé directement aux rôles publics :
seule la dernière explication d'une question du quiz courant est résolue dans
`api_questions`.

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

## Calcul commun des nouveaux matchs

Le navigateur affiche toutes les questions actives (20 dans cette version).
Pour le calcul et la contribution uniquement, il retient les questions dont la
position est renseignée pour tous les candidats, comme `submit-quiz-result`.
Chaque candidat est donc évalué sur les mêmes réponses et avec les mêmes poids.
Le seuil effectif est `max(1, min(min_comparable_answers, nombre_commun))` :
si le corpus commun est inférieur au seuil configuré, il faut répondre à toutes
ses questions. Un corpus vide ne permet aucun enregistrement.

La contribution attend que les 20 questions aient été parcourues, puis transmet
uniquement les réponses communes à la fonction. Celle-ci exige exactement les
identifiants de cette base commune : envoyer toute la grille reçoit une réponse
409, sans écriture. La restauration des 20 écrans conserve donc le contrat de la
fonction existante. Les anciennes sessions reprennent à la première question
manquante en conservant leurs réponses et leur reçu de contribution, pour éviter
une nouvelle comptabilisation. Les tests HTTP simulent entièrement la
base et vérifient l’enregistrement ainsi que le rejet des réponses insuffisantes.

Cette évolution conserve l’identifiant du quiz publié et le RPC
`record_quiz_result`. Le départage des scores égaux utilise désormais le tirage
SHA-256 stable de `tie-break.ts`, identique côté navigateur et côté serveur.
L’ordre éditorial ne décide plus à qui attribuer une contribution.

La migration `20260908102845_correct_royal_positions_preserve_rankings.sql`
publie explicitement les positions relues de Royal, contrairement à un simple
build du frontend qui ne met pas à jour la base. Cette réparation exceptionnelle
du contenu publié s’exécute dans un seul bloc atomique : elle conserve les
anciennes positions et références dans `private.editorial_audit_log`, restaure
les deux triggers d’immutabilité avant de terminer, et annule toute l’opération
si les compteurs, snapshots ou positions des autres candidats ont changé.
Le verrou de collecte empêche une contribution concurrente pendant ce contrôle.
Le quiz conserve son identifiant, ses vingt questions et son historique. La base
commune devient Q01, Q02, Q04, Q09, Q10, Q12 et Q17.

Pour la publication : valider les migrations et les tests sur une base locale
isolée, déployer le nouveau départage serveur, appliquer la migration puis
publier le frontend avec la nouvelle clé de cache de contenu. Les anciens
onglets qui soumettent encore quatre réponses reçoivent un 409 explicite et
doivent être rechargés ; leurs réponses et reçus locaux restent conservés.
Après publication, lire `api_questions` pour vérifier vingt questions et sept
questions communes, puis exécuter le calcul déployé sur ces données pour les
cinq profils. Ne pas ajouter de fausses contributions dans la base publique.

## Rotation et incidents

- faire tourner immédiatement tout secret copié dans un canal non sûr ;
- faire tourner séparément le mot de passe DB, le secret serveur→Edge et la clé
  HMAC ;
- une rotation de clé HMAC invalide seulement les anciens reçus
  d'idempotence, pas les agrégats ;
- désactiver rapidement la collecte avec le réglage
  `anonymous_aggregate_submissions_enabled` ;
- ne jamais exposer la `service_role` au navigateur.
