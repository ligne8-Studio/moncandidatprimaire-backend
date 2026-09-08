# Mon candidat primaire — backend

Code source du backend de [Mon candidat primaire](https://www.moncandidatprimaire.fr/),
publié sous [licence MIT](LICENSE). Il contient l'algorithme de proximité
politique, le modèle de données et le traitement des contributions au classement
collectif, avec Supabase, PostgreSQL et TypeScript / Deno.

Ce dépôt fonctionne indépendamment du frontend Next.js : aucun dossier `../web`
n'est nécessaire pour lire le calcul, exécuter ses tests ou démarrer la base locale.

## Comprendre l'algorithme

Le calcul se trouve dans
[`scoring.ts`](supabase/functions/submit-quiz-result/scoring.ts).
La validation des requêtes et l'enregistrement des contributions se trouvent
dans [`index.ts`](supabase/functions/submit-quiz-result/index.ts).

Le navigateur affiche les 20 questions actives. Une fois ce questionnaire terminé,
il transmet au serveur uniquement les réponses utilisées pour le score commun.

1. Pour le calcul uniquement, ne conserver que les questions actives dont la position est renseignée pour
   **tous les candidats**. Leur nombre dépend du contenu publié ; une position
   inconnue n'est jamais assimilée à une position neutre.
2. Comparer chaque réponse sur une échelle de `-2` à `+2`. Une réponse passée
   (`null`) est exclue pour tous les candidats.
3. Pondérer chaque distance par `1`, ou par le poids d'importance configuré si
   la personne a marqué la question comme importante.
4. Calculer le score de proximité :

   ```text
   score = 100 × (1 − somme(poids × |réponse − position|) / (4 × somme(poids)))
   ```

5. Appliquer à tous le même minimum de réponses comparables :
   `max(1, min(seuil configuré, nombre de questions communes))`. Un questionnaire
   commun vide ne permet aucune contribution. En cas d'égalité de score, l'ordre
   éditorial `tieBreakOrder` départage les candidats ; leurs scores restent égaux.

La fonction serveur recalcule le résultat à partir des réponses et des positions
publiées, sans accepter un score fourni par le navigateur. Les candidats sont
évalués sur les mêmes questions et les mêmes poids. Ce score décrit une proximité
sur ce corpus documenté, pas sur l'ensemble de leurs programmes.

Les [tests du calcul](supabase/functions/submit-quiz-result/scoring.test.ts) et les
[tests HTTP](supabase/functions/submit-quiz-result/index.test.ts) rendent ce
comportement vérifiable. Les changements de code ne recalculent pas les
contributions déjà enregistrées ; voir les
[règles d'exploitation](docs/operations.md#calcul-commun-des-nouveaux-matchs).

## Ce qui est inclus

- un schéma éditorial normalisé et administrable ;
- une version immuable du quiz et de son algorithme ;
- 5 candidats, 40 propositions phares, 20 questions, 100 positions et leurs
  sources ;
- des vues publiques stables pour le frontend ;
- RLS et privilèges explicites sur toutes les tables exposées ;
- les rôles `editor` et `admin`, plus un journal d'audit éditorial ;
- un bucket public `editorial-assets`, les cinq portraits versionnés et une
  écriture réservée au staff ;
- une Edge Function qui recalcule chaque résultat puis ne conserve qu'un
  compteur agrégé, avec idempotence et limitation quotidienne par empreinte ;
- une publication automatique du classement par cohortes de 10 contributions,
  sans exposer les deltas individuels ;
- des tests pgTAP, tests Deno, types TypeScript générés et CI.

Sur une nouvelle installation, le classement démarre à zéro. Aucun résultat de
lancement n'est prérempli : `live_match_count` contient le cumul privé collecté et
la vue publique ne voit que les cohortes complètes déjà relâchées.

## Architecture

```text
Navigateur
  ├─ lecture publique ───────────────> vues api_* + RLS
  └─ résultat d'un quiz terminé
       └─ POST /api/quiz-results ───> Next.js (secret serveur)
            └─ submit-quiz-result ──> calcul éphémère côté Edge
                 └─ RPC atomique ──> compteur privé
                                      └─ cohorte de 10 ──> vue publique
```

Le traitement du quiz ne conserve pas les réponses détaillées, les scores
individuels, les IP brutes ou les user-agents. Il ne crée aucun compte participant.
Des empreintes temporaires servent à l'idempotence et à la limitation des abus ;
les comptes Auth sont réservés au staff. Voir [docs/privacy.md](docs/privacy.md).

## Démarrage local

Prérequis : Node.js 22 et Deno 2. Docker est nécessaire uniquement pour la base
Supabase locale.

```bash
git clone https://github.com/ligne8-Studio/moncandidatprimaire-backend.git
cd moncandidatprimaire-backend
npm ci
npm run functions:format-check
npm run functions:test
npm run functions:check
```

Ces tests simulent les accès à la base : ils ne nécessitent ni compte Supabase,
ni secret de production, ni Docker.

Pour démarrer également la base et tester son schéma :

```bash
npm run db:start
npm run db:reset
npm run assets:upload:local
npm run db:lint
npm run db:test
```

`db:reset` réinitialise uniquement la base locale de ce projet.
Supabase local utilise volontairement les ports `55320–55329`, afin de ne pas
interrompre d'autres projets Supabase présents sur la machine.

Les variables attendues sont décrites dans [`.env.example`](.env.example).
Utilisez vos propres identifiants et secrets pour connecter une instance au
frontend. Les fichiers `.env` réels sont exclus de Git.

## Contenu et migrations

Les migrations sont dans `supabase/migrations/` :

1. `initial_schema` crée le modèle, la sécurité, les vues et la RPC interne ;
2. `seed_editorial_content` charge le snapshot éditorial de lancement ;
3. `harden_private_table_policies` explicite le refus d'accès client aux tables
   réservées au service ;
4. `admin_backoffice_workflows` fournit le profil staff minimal, le journal
   d'audit admin, le clonage de brouillon et la publication atomique ;
5. `harden_admin_rpc_surface` conserve les RPC publiques tout en isolant leurs
   implémentations privilégiées dans le schéma privé ;
6. `admin_atomic_save_workflows` sécurise les écritures relationnelles ;
7. `activate_real_community_rankings` supprime les chiffres de lancement,
   active la collecte réelle et publie les agrégats par cohortes ;
8. `add_question_context_revisions` sépare les explications pédagogiques des
   données de score immuables et publie un premier contexte pour les 20
   questions.

Le snapshot reproductible se trouve dans `content/editorial-content.json`.
`npm run content:generate` régénère déterministement la migration de contenu.
L'import historique `npm run content:import` nécessite séparément `../web` et
ses dépendances installées. Il n'est pas requis pour utiliser ce dépôt : le
snapshot est déjà fourni. Pour une instance en service, la base publiée reste
la source de vérité ; régénérer le snapshot ne met pas à jour les données distantes.

Les portraits source sont versionnés dans `assets/candidates/`. Les lignes
`media_assets` pointent vers Storage tout en conservant un fallback frontend.
Après les migrations, `npm run assets:upload:linked` charge les binaires sans
les rendre modifiables par le navigateur public.

Une version publiée du quiz est immuable. Toute modification de question,
barème, candidat inclus ou position demande de cloner une nouvelle version en
`draft`, de la relire, puis de la publier. Cela évite de changer rétroactivement
la signification des classements.

Les paragraphes explicatifs suivent un cycle distinct dans
`question_context_revisions` : un éditeur enregistre l'unique brouillon avec
`save_question_context_draft()`, puis un admin le publie avec
`publish_question_context_revision()`. Les révisions publiées sont append-only
et la plus récente alimente `api_questions`. Une clarification ne crée donc pas
de nouvelle version de score et ne remet jamais le classement à zéro.

## Déploiement Supabase

Ne placez jamais le mot de passe de la base dans un argument CLI ou un fichier
versionné.

```bash
export SUPABASE_DB_PASSWORD='...'
npx supabase link --project-ref your-project-ref
npx supabase db push --linked --dry-run
npx supabase db push --linked
npm run assets:upload:linked
npx supabase functions deploy submit-quiz-result \
  --project-ref your-project-ref --use-api
unset SUPABASE_DB_PASSWORD
```

Les secrets `QUIZ_SUBMISSION_SHARED_SECRET` et `QUIZ_HASH_SECRET` doivent être
définis dans les secrets Edge Function. Le premier doit aussi exister uniquement
dans l'environnement serveur Vercel du frontend Next.js, sous le nom
`SUPABASE_QUIZ_SUBMISSION_SECRET`. Il ne doit jamais porter le préfixe
`NEXT_PUBLIC_`.

Le déploiement du backend ne déploie jamais `../web`.

## Administration

Le fichier local `supabase/config.toml` désactive l'inscription Auth publique,
mais cette configuration n'est volontairement pas poussée sans connaître les
URL de production. Avant d'ouvrir l'administration, désactivez aussi les
inscriptions dans le Dashboard Supabase et configurez les URL de redirection.
Le premier compte staff doit ensuite être créé ou invité depuis le Dashboard,
puis promu manuellement :

```sql
insert into private.staff_members (user_id, role)
values ('00000000-0000-0000-0000-000000000000', 'admin');
```

Ne créez pas de route publique permettant de devenir administrateur. Les
éditeurs préparent uniquement des brouillons ; seuls les admins publient,
modifient les réglages opérationnels ou gèrent les classements. Dans
l'interface, privilégier l'archivage aux suppressions.

Le navigateur ne lit jamais `auth.users` ni `private.staff_members`. Il obtient
uniquement le profil de la session courante via `get_my_staff_profile()`. La
gestion des autres membres staff reste volontairement une opération de
plateforme, à effectuer avec l'API Auth admin côté serveur ou dans le Dashboard
Supabase. Le backoffice ne doit jamais embarquer de `service_role`.

`clone_quiz_version()` crée en une transaction une version éditable avec ses
questions, positions, preuves, compteurs à zéro et un snapshot `collected` vide
en brouillon. `publish_quiz_version()` est réservé aux admins et bascule les
versions de façon atomique après les contrôles de complétude du schéma.

Le journal d'audit identifie les écritures réalisées avec le JWT du membre du
staff. Les migrations, l'éditeur SQL du Dashboard et la `service_role` n'ont pas
de `auth.uid()` : les futures routes d'administration doivent donc écrire avec
le client authentifié de l'utilisateur, pas avec une clé de service partagée.

## Documentation

- [Modèle de données](docs/data-model.md)
- [Sécurité et confidentialité](docs/privacy.md)
- [Exploitation et mises en production](docs/operations.md)

## Contribuer

Ouvrez une issue pour discuter d'un problème ou proposez une pull request.
Pour une modification du calcul, expliquez son effet sur les scores et ajoutez
un cas de test reproductible. Pour une correction éditoriale, fournissez les
sources et leurs dates. Exécutez les contrôles correspondant aux fichiers modifiés ;
la CI vérifie aussi les migrations et les tests de la base.

Ne joignez aucun secret, export de production ou donnée personnelle à une issue
ou une pull request.

## Licence

Le code et la documentation originaux de ce dépôt sont sous [licence MIT](LICENSE).
Vous pouvez les utiliser, modifier et redistribuer en conservant la notice de
copyright et la licence.

Cette licence n'accorde aucun droit supplémentaire sur les contenus de tiers,
notamment les portraits des candidats, les marques et les documents cités comme
sources. Leurs droits respectifs doivent être vérifiés avant réutilisation.
Les dépendances conservent leurs propres licences.
