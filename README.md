# Mon candidat primaire — backend

Backend Supabase versionné pour le site **Mon candidat primaire**. Ce dépôt est
indépendant du frontend Next.js situé dans `../web`.

## Ce qui est inclus

- un schéma éditorial normalisé et administrable ;
- une version immuable du quiz et de son algorithme ;
- 5 candidats, 40 propositions phares, 20 questions, 100 positions et leurs
  sources ;
- des vues publiques stables pour le frontend ;
- RLS et privilèges explicites sur toutes les tables exposées ;
- les futurs rôles `editor` et `admin`, plus un journal d'audit éditorial ;
- un bucket public `editorial-assets`, les cinq portraits versionnés et une
  écriture réservée au staff ;
- une Edge Function prête à calculer un résultat puis à ne conserver qu'un
  compteur agrégé, actuellement désactivée tant que le socle est synthétique ;
- des tests pgTAP, tests Deno, types TypeScript générés et CI.

Le classement initial de 12 480 résultats est marqué `synthetic` en base. Les
futures contributions réelles sont stockées séparément dans
`live_match_count`.

## Architecture

```text
Navigateur
  ├─ lecture publique ───────────────> vues api_* + RLS
  └─ contribution consentie
       └─ POST /api/quiz-results ───> Next.js (secret serveur)
            └─ submit-quiz-result ──> calcul éphémère côté Edge
                 └─ RPC atomique ──> compteur agrégé uniquement
```

Les réponses, scores individuels, candidats favoris, comptes Auth, IP brutes et
user-agents ne sont jamais enregistrés. Voir [docs/privacy.md](docs/privacy.md).

## Démarrage local

Prérequis : Node.js 22, Docker et Deno 2.

```bash
npm install
npm run db:start
npm run db:reset
npm run assets:upload:local
npm run db:lint
npm run db:test
deno test supabase/functions/submit-quiz-result
npm run functions:check
```

Supabase local utilise volontairement les ports `55320–55329`, afin de ne pas
interrompre d'autres projets Supabase présents sur la machine.

## Contenu et migrations

Les migrations sont dans `supabase/migrations/` :

1. `initial_schema` crée le modèle, la sécurité, les vues et la RPC interne ;
2. `seed_editorial_content` charge le snapshot éditorial de lancement ;
3. `harden_private_table_policies` explicite le refus d'accès client aux tables
   réservées au service.

Le snapshot reproductible se trouve dans `content/editorial-content.json`.
`npm run content:generate` régénère déterministement la migration de contenu.
L'import depuis `../web` est conservé uniquement pour tracer la migration
initiale ; Supabase devient ensuite la source de vérité.

Les portraits source sont versionnés dans `assets/candidates/`. Les lignes
`media_assets` pointent vers Storage tout en conservant un fallback frontend.
Après les migrations, `npm run assets:upload:linked` charge les binaires sans
les rendre modifiables par le navigateur public.

Une version publiée du quiz est immuable. Toute modification de question,
barème, candidat inclus ou position demande de cloner une nouvelle version en
`draft`, de la relire, puis de la publier. Cela évite de changer rétroactivement
la signification des classements.

## Déploiement Supabase

Ne placez jamais le mot de passe de la base dans un argument CLI ou un fichier
versionné.

```bash
export SUPABASE_DB_PASSWORD='...'
npx supabase link --project-ref ejmgcqddrrfbrflguvku
npx supabase db push --linked --dry-run
npx supabase db push --linked
npm run assets:upload:linked
npx supabase functions deploy submit-quiz-result \
  --project-ref ejmgcqddrrfbrflguvku --use-api
unset SUPABASE_DB_PASSWORD
```

Les secrets `QUIZ_SUBMISSION_SHARED_SECRET` et `QUIZ_HASH_SECRET` doivent être
définis dans les secrets Edge Function. Le premier doit aussi exister uniquement
dans l'environnement serveur Next.js, sous le nom
`SUPABASE_QUIZ_SUBMISSION_SECRET`.

Le déploiement du backend ne déploie jamais `../web`.

## Administration future

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

Le journal d'audit identifie les écritures réalisées avec le JWT du membre du
staff. Les migrations, l'éditeur SQL du Dashboard et la `service_role` n'ont pas
de `auth.uid()` : les futures routes d'administration doivent donc écrire avec
le client authentifié de l'utilisateur, pas avec une clé de service partagée.

## Documentation

- [Modèle de données](docs/data-model.md)
- [Sécurité et confidentialité](docs/privacy.md)
- [Exploitation et mises en production](docs/operations.md)
