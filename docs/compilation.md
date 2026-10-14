# Compilation

Kelmscott compile les sites lui-même, sans yarn ni script du thème, avec une **toolchain partagée** (`toolchain/`) : les dépendances npm du thème (PostCSS, cssnano, leaflet…) et pagefind, installées une seule fois avec npm par `bin/steps/sandbox` dans `/usr/local/lib/kelmscott/toolchain`, en lecture seule pour les builds.

`sandbox/compile` remplace le `node_modules` du site par un lien vers la toolchain, lance `hugo --minify`, puis pagefind depuis le dossier du thème : sa configuration (dossier du site, pages indexées, sélecteurs exclus) est dans le `pagefind.yml` du thème.

Il n'y a donc ni `node_modules`, ni cache npm par site, et aucun script npm ou du thème n'est exécuté.

Contraintes :

- le site utilise le thème osuny dans `themes/osuny`, dans une version qui fournit `pagefind.yml` ;
- le site n'a pas d'autres dépendances npm que le thème : les sites qui en ont continuent d'être compilés par leur propre CI ;
- `toolchain/package.json` suit le `package.json` du thème : une dépendance ajoutée, retirée ou mise à jour dans le thème doit l'être aussi dans la toolchain (puis `npm install --package-lock-only` dans `toolchain/`).
