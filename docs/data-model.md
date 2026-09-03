# Modèle de données

## Contenu éditorial

| Domaine | Tables principales | Rôle |
| --- | --- | --- |
| Scrutin | `campaigns`, `quiz_versions` | Campagne et versions immuables du quiz |
| Candidats | `parties`, `candidates`, `media_assets` | Profils, identité visuelle et portraits |
| Quiz | `themes`, `questions`, `answer_scale_options` | Grille et libellés de réponse |
| Positions | `candidate_positions`, `position_sources` | Valeur −2…+2, niveau de preuve et sources |
| Propositions | `candidate_highlights`, `highlight_sources` | Mesures phares affichées sur les fiches |
| Sources | `sources`, `source_candidates`, `source_themes` | Registre documentaire normalisé |
| Configuration | `site_settings` | Fonctionnalités et contrat public de données |

`quiz_version_candidates` fige la liste, l'ordre d'affichage et l'ordre de
départage de chaque version. Une position non documentée est une vraie ligne
avec `documentation_status = 'undocumented'` et `stance is null` : elle ne peut
donc pas être confondue avec une jointure oubliée.

Le workflow de backoffice ne modifie jamais ces données dans une version
publiée. `clone_quiz_version()` reconstruit les identifiants de questions et de
positions dans un nouveau brouillon, puis recopie leurs liens de preuve.
`publish_quiz_version()` sélectionne un snapshot relu, archive l'ancienne
version courante et publie la nouvelle dans une même transaction.

## Classement communautaire

`community_ranking_counters` contient le cumul réel collecté et n'est lisible
que par un admin ou la clé serveur. `community_ranking_snapshots` et
`community_ranking_entries` contiennent uniquement le dernier cumul relâché.
La RPC d'enregistrement copie atomiquement tous les compteurs vers le snapshot
dès que 10 nouvelles contributions sont en attente. La vue
`api_community_rankings` expose donc un classement réel qui démarre à zéro et
ne révèle jamais un delta individuel en temps réel.

Les origines autorisées sont `collected` pour les contributions du site et
`imported` pour un éventuel jeu externe réel, explicitement contrôlé par un
administrateur. Un snapshot `collected` ne peut pas être saisi arbitrairement
depuis le backoffice : ses valeurs doivent correspondre aux compteurs privés.

Les tables privées `quiz_submission_receipts` et
`quiz_rate_limit_buckets` ne contiennent que des HMAC à durée de vie limitée.
Elles ne permettent pas de retrouver les réponses ni le candidat arrivé en
tête.

## Contrat frontend

Les vues publiques sont les seules formes que le frontend doit mapper :

- `api_current_quiz`
- `api_candidates`
- `api_questions`
- `api_sources`
- `api_answer_scale`
- `api_community_rankings`

Elles utilisent `security_invoker = true`, donc les RLS des tables sous-jacentes
restent actives. Les tables de travail en `draft` ne sont jamais visibles avec
la clé publique.

`api_community_rankings` expose `match_count`, `total_match_count`,
`match_percentage`, `rank_position`, `has_results`, les drapeaux de
fonctionnalité et la date du dernier relâchement. Tant que le premier lot n'est
pas complet, les cinq candidats ont un compteur nul et aucun rang.

Le backoffice authentifié travaille sur les tables normalisées, toujours sous
RLS. Son unique surface privée est constituée de RPC bornées : profil staff de
la session, journal d'audit admin et workflows de version. Aucune RPC ne liste
les comptes Auth ni les autres membres du staff.

## État éditorial importé

- 5 candidats et 2 partis ;
- 10 thèmes ;
- 20 questions et 100 couples question/candidat ;
- 62 positions documentées, 38 explicitement non documentées ;
- 27 sources conservées, dont 4 anciens placeholders archivés ;
- 73 liens position/source ;
- 40 propositions phares et 40 liens de preuve.

Trois métadonnées source/thème manquantes dans les constantes historiques ont
été normalisées au moment de l'import. Les tests fixent ces invariants.
