# Portraits Maurel et Verdier — septembre 2026

Illustrations générées avec `image_gen`, d’après des photographies réelles vérifiées visuellement. Les photographies de référence ne sont pas redistribuées avec le code MIT.

Références d’identité :

- [Emmanuel Maurel, photographie officielle de l’Assemblée nationale](https://www.assemblee-nationale.fr/dyn/deputes/PA842271), portrait actuel avec lunettes.
- [Fabien Verdier, site de candidature](https://fabienverdier.fr/), photographie de septembre 2026.

Les portraits existants de Guedj et Royal ont servi de référence pour la gravure et les couleurs. Chaque portrait a été généré séparément. Une deuxième édition par `image_gen` a remplacé le damier peint par un fond blanc. Le composant utilise un filtre SVG pour rendre le papier blanc transparent à l’affichage, en conservant le fichier généré ; la conversion WebP ne change que le format et la taille (900 × 1125, qualité 88).

Fichiers : `maurel.webp` et `verdier.webp`, dans `web/public/candidates` et `backend/assets/candidates`.

## maurel

Prompt de génération :

```text
Use case: identity-preserve / style-transfer. Create one isolated editorial portrait for a neutral French civic comparison website. Image 1 is the CURRENT identity reference: Emmanuel Maurel's official National Assembly portrait, and must be faithfully followed: broad oval face, high receding forehead and balding crown, short dark brown hair at the sides, slim rectangular black glasses, clean-shaven face, reserved friendly expression, about 53 years old. Image 2 is STYLE ONLY: the existing engraved Guedj portrait from the website. Do not copy that person's facial features, hair or beard. Draw Emmanuel Maurel waist-up, head facing front with a very slight three-quarter shoulder angle, in a charcoal suit, light shirt and plain dark tie. Match the same realistic hand-engraved ink and fine pencil cross-hatching editorial treatment with lightly warm cream skin and deep charcoal clothes; subtly desaturated, dignified, equal visual prominence. Preserve precise identity and glasses. Portrait 4:5 ratio. Full head with generous clearance at the top, entire shoulders, lower torso reaches the bottom. TRUE transparent background with alpha, no paper rectangle, no shadow or scenery, no frame, no writing, no logo, no flag, no added objects. Only one person.
```

## verdier

Prompt de génération :

```text
Use case: identity-preserve / style-transfer. Create one isolated editorial portrait for a neutral French civic comparison website. Image 1 is the current identity reference: Fabien Verdier's September 2026 campaign photograph, which must be faithfully followed: slim oval angular face, tall forehead, short dark brown hair brushed up and sideways with receding temples, dark brown eyes, short neatly trimmed stubble beard and moustache, his characteristic broad tooth-showing smile, about 45 years old. Image 2 is STYLE ONLY: the existing engraved Guedj portrait from the website. Do not copy that person's facial features, hair or beard. Draw Fabien Verdier waist-up, head facing front with a slight three-quarter shoulder angle matching his photo, in a charcoal/navy suit, light blue shirt and plain dark tie. Match the same realistic hand-engraved ink and fine pencil cross-hatching editorial treatment with lightly warm cream skin and deep charcoal clothes; subtly desaturated, dignified, equal visual prominence. Preserve precise identity, smile, hair and short beard from image1. Portrait 4:5 ratio. Full head with generous clearance at the top, entire shoulders, lower torso reaches the bottom. TRUE transparent background with alpha, no paper rectangle, no shadow or scenery, no frame, no writing, no logo, no flag, no added objects. Only one person.
```

## Édition du fond

```text
Edit ONLY the background of this existing portrait. Preserve the person's exact face, glasses or beard, hair, clothing, engraved drawing treatment, dimensions and composition without any change. Remove the gray-and-white checkerboard pattern completely. It is painted into this image and is NOT transparency. Replace every background pixel outside the silhouette with flat pure white RGB 255,255,255. No gray, no pattern, no texture, no shadows, no outline, no gradient, no checkerboard. Keep the portrait itself identical. Output one image. The image will be blended on the website using its pure white backdrop.
```

