# Ajout de Maurel et Verdier — 8 septembre 2026

Sept fiches sont publiées, avec huit propositions et un portrait par candidat.
Le quiz conserve ses vingt questions. Les six candidats éligibles sont comparés
sur les mêmes sept questions : Q01, Q02, Q04, Q09, Q10, Q12 et Q17.

Fabien Verdier n’entre pas dans le score ni dans le classement. Ses huit
propositions publiées ne permettent pas de coder les questions communes
(ISF, importations, SMIC, nucléaire, renouvelables, Mercosur, hôpital) avec une
précision suffisante. Aucune absence de source n’est remplacée par une position
neutre. Sa fiche explique cette exclusion, conformément au choix de l’éditeur.

## Sources et portée

- [Maurel : candidature annoncée le 4 septembre 2026](https://g-r-s.fr/emmanuel-maurel-candidat-a-la-primaire-de-la-gauche-socialiste/).
- [Texte personnellement cosigné en août 2024](https://g-r-s.fr/choix-du-premier-ministre-pour-un-sursaut-rapide/) : fiscalité, salaires, retraites et hôpital. Les dates restent visibles ; ces mesures ne sont pas présentées comme un programme personnel de 2026.
- [Bilan de mandat de Maurel, juin 2025](https://emmanuelmaurel.eu/wp-content/uploads/2025/06/Maquette-bilan-mandat-2024-2025_Web-Simples.pdf) : commerce, Mercosur (pages 5–6), installation médicale (page 8).
- [Programme écologique de la GRS, congrès de juin 2026](https://g-r-s.fr/wp-content/uploads/2026/08/Ecologie-republicaine.pdf), page 10 : nouveaux réacteurs, renouvelables et filière solaire. Ces positions sont explicitement attribuées à son parti, avec une confiance moyenne. Pour Q10, le codage +1 suit le même critère que Guedj : une seule des deux filières solaire/éolien est précisément documentée.
- [Site officiel de Fabien Verdier](https://fabienverdier.fr/), consulté le 8 septembre : les huit propositions reprennent ses priorités publiques, sans les convertir en positions sur des questions différentes. La page n’affiche pas de date de publication ; la date de consultation est indiquée comme telle dans le titre de la source.

Maurel et Guedj ont actuellement les mêmes positions codées sur les sept
questions communes. Leur égalité est conservée ; le tirage reproductible
existant les départage avec la même chance, sans fabriquer de différence.

## Protection des résultats existants

La version reste `2026-09-03-v1`. La migration d’ajout prend le même verrou que
les contributions, ajoute uniquement des compteurs à zéro, puis compare les
anciennes lignes avant/après : compteurs privés, lots publics, pourcentages,
ordre, snapshots, questions et positions existantes. Toute divergence annule
la transaction. Les reçus et réponses antérieures ne sont pas retraités.

`is_matching_eligible` appartient à l’association candidat/version. La règle est
appliquée dans le frontend, la fonction Edge et la fonction SQL de comptage.
Une version clonée conserve le statut et son motif. Les vues conservent
`security_invoker`, RLS et leurs privilèges existants. Le multiplicateur visuel
×10 demandé pour les tests n’est pas changé.
