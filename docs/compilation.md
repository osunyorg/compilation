# Compilation

Kelmscott compile les sites lui-même, sans yarn ni script du thème, avec une **toolchain partagée** (`toolchain/`) : les dépendances npm du thème (PostCSS, cssnano, leaflet…) et pagefind, installées une seule fois avec npm par `bin/steps/sandbox` dans `/usr/local/lib/kelmscott/toolchain`, en lecture seule pour les builds.

`sandbox/compile` remplace le `node_modules` du site par un lien vers la toolchain, lance `hugo --minify`, puis pagefind depuis le dossier du thème : sa configuration (dossier du site, pages indexées, sélecteurs exclus) est dans le `pagefind.yml` du thème.

Il n'y a donc ni `node_modules`, ni cache npm par site, et aucun script npm ou du thème n'est exécuté.

Contraintes :

- le site utilise le thème osuny dans `themes/osuny`, dans une version qui fournit `pagefind.yml` ;
- le site n'a pas d'autres dépendances npm que le thème : les sites qui en ont continuent d'être compilés par leur propre CI ;
- `toolchain/package.json` liste ce que le build du thème utilise réellement (son `postcss.config.js` et pagefind), et non une copie de son `package.json`. Seule exception, `dxfl`, utilisé par la synchronisation et non par le build.

## Mise à jour de la toolchain

Sur un poste de développement :

```bash
kelmscott/toolchain/update
```

Le script met à jour `package-lock.json` dans les plages de `package.json`, sans rien installer ni exécuter. Pour ajouter, retirer ou changer la plage d'une dépendance, modifier d'abord `package.json`. Commiter ensuite `package-lock.json` : sur la VM, `~/kelmscott/bin/update` réinstalle la toolchain à l'identique (`npm ci`).
