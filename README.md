# Kelmscott

![Kelmscott Press](kelmscott-press.jpg)

Ce référentiel doit être cloné sur la machine Kelmscott.

```
app/        interface web et réception des demandes de l'admin Osuny (Sinatra)
bin/        administration de la machine, lancée à la main
sandbox/    récupération et compilation des sites, qui exécutent le code des dépôts, sans droits
sync/       synchronisation des sites compilés, seule à recevoir les secrets
toolchain/  dépendances du thème, installées une fois et partagées par tous les builds
```

## Installation d'une VM

### Prérequis

- Une VM **Ubuntu 24.04 LTS** neuve, avec une IP fixe : les hébergeurs des sites peuvent la mettre en liste blanche.
- Un accès SSH avec l'utilisateur `ubuntu`, qui a les droits sudo.
- Un nom de domaine (par exemple `kelmscott.osuny.org`) dont l'enregistrement DNS pointe vers l'IP de la VM.
- De l'espace disque : chaque site garde son dépôt (sources, historique git) et sa compilation, soit quelques dizaines de Mo par site.

### 1. Système et pare-feu

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git ufw
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
```

### 2. Kelmscott

Le dépôt doit être cloné dans `~/kelmscott` : le service systemd et la configuration nginx utilisent ce chemin.

```bash
cd ~
git clone https://github.com/osunyorg/kelmscott.git
cd kelmscott
bin/setup
```

`bin/setup` installe :

- les paquets système (compilation de Ruby, libsodium, rsync, rclone, nginx) ;
- Ruby, Node et Hugo, via mise ;
- l'application Sinatra, nginx en reverse proxy, et le service `kelmscott-puma` ;
- le sandbox des builds (`bin/setup-sandbox`, voir [Cloisonnement des builds](#cloisonnement-des-builds)).

Il faut ensuite ouvrir une nouvelle session SSH, pour que mise soit actif dans le shell.

### 3. Domaine et HTTPS

Remplacer `server_name` par le domaine de la VM dans `/etc/nginx/sites-available/kelmscott.conf`, puis :

```bash
sudo systemctl reload nginx
bin/setup-ssl
```

### 4. Clés de chiffrement

```bash
bin/setup-keys
```

Reporter les trois valeurs affichées dans la configuration de l'admin Osuny, et sauvegarder la clé privée hors de la machine (voir [Clés de chiffrement](#clés-de-chiffrement)).

### 5. Démarrage

```bash
bin/start
```

### 6. Restriction de sudo (recommandé)

Sur les images cloud, `ubuntu` a généralement un sudo complet sans mot de passe. Les builds n'y ont pas accès (ils tournent sous `kelmscott-build`), mais si le service était compromis, il obtiendrait root. Une fois l'installation terminée, on peut ne lui laisser que le sandbox et le redémarrage du service, en remplaçant la ligne `ubuntu` de `/etc/sudoers.d/90-cloud-init-users` par :

```
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl restart kelmscott-puma.service, /usr/bin/systemctl start kelmscott-puma.service
```

`bin/setup` et `bin/update` ont alors besoin d'un autre compte administrateur. Faire la modification avec `sudo visudo -f /etc/sudoers.d/90-cloud-init-users`, en gardant une deuxième session SSH ouverte pour ne pas se retrouver bloqué.

## Protocole de vérification

À dérouler après l'installation et après toute modification du sandbox. Dans les commandes, `DOMAINE` est le domaine de la VM.

### 1. Services

```bash
systemctl is-active kelmscott-puma nginx
id kelmscott-build
ls -l /usr/local/sbin/kelmscott-sandbox /usr/local/lib/kelmscott /etc/sudoers.d/kelmscott
```

Attendu : deux fois `active`, l'utilisateur `kelmscott-build` existe, et les fichiers appartiennent à `root`.

### 2. Sandbox

```bash
sudo -n /usr/local/sbin/kelmscott-sandbox
sudo -n /usr/local/sbin/kelmscott-sandbox compile ../.. site
sudo -n /usr/local/sbin/kelmscott-sandbox fetch test site file:///etc
```

Attendu : `commande inconnue`, `université invalide`, puis `URL invalide`, sans demande de mot de passe.

### 3. HTTP

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://DOMAINE/
curl -s -w ' %{http_code}\n' -X POST https://DOMAINE/test/site -H 'Content-Type: application/json' -d '{}'
curl -s https://DOMAINE/test/inconnu/badge.svg | grep -o '<title>[^<]*'
```

Attendu : `200`, puis `Unauthorized 401`, puis `Kelmscott : inconnu`.

### 4. Isolation

Créer un dépôt de test public (par exemple `kelmscott-canary`) qui tente de sortir du sandbox. Le seul code du dépôt que Kelmscott exécute est celui que Hugo confie à Node, comme `postcss.config.js` : le canary s'y loge, et lève la restriction de Node dans sa configuration Hugo, comme le ferait un dépôt malveillant.

`hugo.toml` :

```toml
baseURL = "https://example.org/"
disableKinds = ["taxonomy", "term", "RSS", "sitemap", "robotsTXT", "404"]

[security.node.permissions]
allowChildProcess = ["postcss"]
```

`layouts/index.html` :

```html
<html><body>{{ with resources.Get "canary.css" | postCSS }}{{ .RelPermalink }}{{ end }}</body></html>
```

`assets/canary.css` :

```css
body {}
```

`postcss.config.js` :

```js
require('child_process').execSync('sh canary.sh > canary.txt 2>&1')
module.exports = { plugins: [] }
```

`themes/osuny/pagefind.yml` :

```yaml
site: ../../public
```

`canary.sh` :

```sh
echo "== utilisateur"; id
echo "== clé privée"; cat /home/*/kelmscott/app/config/kelmscott.key
echo "== sites visibles"; ls /srv/kelmscott/sites
echo "== logs des autres sites"; ls /srv/kelmscott/state
echo "== sudo"; sudo -n true
echo "== écriture hors du site"; touch /etc/canary /srv/kelmscott/canary
echo "== écriture dans /tmp"; touch /tmp/canary && echo "ok (privé)"
echo "== toolchain en lecture seule"; touch node_modules/canary
echo "== réseau"; curl -sI https://registry.npmjs.org | head -1
```

Lancer sa publication depuis la VM, puis lire le résultat, écrit dans le dépôt :

```bash
curl -X POST https://DOMAINE/test/canary \
  -H "Authorization: Bearer $(cat ~/kelmscott/app/config/kelmscott.token)" \
  -H "Content-Type: application/json" \
  -d '{"git_url": "https://github.com/<compte>/kelmscott-canary.git", "sync_method": "dxfl", "variables": {"DXFL_BUCKET": "test"}}'
sleep 60
cat /srv/kelmscott/sites/test/canary/repository/canary.txt
```

Attendu :

| Test | Résultat attendu |
|---|---|
| utilisateur | `kelmscott-build` |
| clé privée | `No such file or directory` |
| sites visibles | `test` seulement |
| logs des autres sites | `No such file or directory` |
| sudo | refusé (`no new privileges`) |
| écriture hors du site | `Read-only file system` |
| écriture dans /tmp | `ok (privé)` |
| toolchain en lecture seule | `Read-only file system` |
| réseau | `HTTP/2 200` |

La synchronisation échoue ensuite, faute de clés dxfl : c'est normal, et le badge de `test/canary` passe à `échec`, ce qui vérifie que les échecs remontent bien du sandbox.

### 5. Publication réelle

Activer Kelmscott sur un site dans l'admin Osuny et le publier. Attendu : le log du site (page `https://DOMAINE/<université>/<site>`) se termine par les durées et le poids, le badge passe à `succès`, et le site est en ligne.

### 6. Nettoyage

```bash
sudo rm -rf /srv/kelmscott/sites/test /srv/kelmscott/state/test
```

## Mise à jour

```bash
cd kelmscott
git pull
bin/update
bin/restart
```

`bin/update` réinstalle les copies root du sandbox. Lors de la première mise à jour qui l'ajoute, lancer aussi `bin/setup-sandbox` à la main : bash continue d'exécuter l'ancienne version de `bin/update`, remplacée pendant le `git pull`.

## Tests

```bash
cd app
bundle install
bundle exec rake test
```

Les tests couvrent l'interface web, les demandes de l'admin (authentification, validation, déchiffrement), le badge, et le déroulement d'une publication avec un sandbox et une synchronisation simulés. Le sandbox lui-même ne tourne que sur Linux avec systemd : il se vérifie sur la machine, avec le [protocole de vérification](#protocole-de-vérification).

## Clés de chiffrement

Les secrets de synchronisation des sites (mots de passe SFTP, clés AWS…) sont saisis dans l'admin Osuny, qui les chiffre immédiatement avec la **clé publique** de Kelmscott. Seul Kelmscott possède la **clé privée** permettant de les déchiffrer : l'admin ne stocke et ne transmet donc jamais de secret en clair.

Le chiffrement utilise les [sealed boxes de libsodium](https://doc.libsodium.org/public-key_cryptography/sealed_boxes) (Curve25519), via la gem `rbnacl`, des deux côtés.

En plus de la paire de clés, un **jeton** partagé authentifie les requêtes de l'admin vers Kelmscott.

### Création

```bash
cd kelmscott
bin/setup-keys
```

Le script crée, s'ils n'existent pas encore :

- `app/config/kelmscott.key` : la clé privée (32 octets, en base 64), lisible uniquement par l'utilisateur courant ;
- `app/config/kelmscott.token` : le jeton d'authentification.

Ces fichiers ne sont pas versionnés. Le script affiche ensuite les valeurs à reporter dans la configuration de l'admin Osuny (`config/application.yml` ou variables d'environnement) :

```yaml
KELMSCOTT_URL: https://kelmscott.osuny.org
KELMSCOTT_PUBLIC_KEY: <clé publique affichée>
KELMSCOTT_TOKEN: <jeton affiché>
```

Le script peut être relancé sans risque pour réafficher ces valeurs : il ne remplace jamais une clé existante.

### Sauvegarde et renouvellement

La clé privée doit être sauvegardée hors de la machine (gestionnaire de mots de passe). Si elle est perdue ou renouvelée, tous les secrets enregistrés dans l'admin deviennent indéchiffrables et doivent être ressaisis, site par site, après mise à jour de `KELMSCOTT_PUBLIC_KEY`.

Pour renouveler la paire de clés :

```bash
rm app/config/kelmscott.key
bin/setup-keys
bin/restart
```

Le jeton se renouvelle de la même manière avec `app/config/kelmscott.token`.

## Requêtes de l'admin Osuny

L'admin demande une compilation avec une requête `POST` sur `/:university/:site` :

```bash
curl -X POST https://kelmscott.osuny.org/noesya/noesya-www \
  -H "Authorization: Bearer $KELMSCOTT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "git_url": "https://github.com/osunyorg/noesya-www.git",
    "sync_method": "s3",
    "variables": {
      "S3_BUCKET": "www.noesya.coop",
      "S3_REGION": "fr-par",
      "AWS_ACCESS_KEY_ID": "SCW...",
      "AWS_SECRET_ACCESS_KEY": "<valeur chiffrée, en base 64>"
    }
  }'
```

- `git_url` doit être une URL `https://` ;
- `sync_method` vaut `sftp`, `dxfl`, `rsync` ou `s3` ;
- `variables` n'accepte que les clés prévues pour la méthode choisie (même liste blanche que `Communication::Website::Variable` dans l'admin) ;
- les secrets (`SFTP_PASSWORD`, `RSYNC_SSH_PRIVATE_KEY`, `AWS_SECRET_ACCESS_KEY`) sont envoyés tels que stockés par l'admin, chiffrés : Kelmscott les déchiffre en mémoire et ne les écrit nulle part.

Réponses :

| Code | Signification |
|------|---------------|
| 202 | Demande acceptée, le clone/pull, la compilation puis la synchronisation s'exécutent en arrière-plan |
| 400 | Paramètres invalides, ou secret impossible à déchiffrer (mauvaise clé publique dans l'admin) |
| 401 | Jeton absent ou invalide |
| 415 | Le corps n'est pas en `application/json` |
| 503 | Les clés n'ont pas été générées (`bin/setup-keys`) |

Les compilations d'un même site sont exécutées l'une après l'autre. Les secrets ne sont pas transmis à la compilation (Hugo et le thème exécutent du code issu du dépôt) ; ils sont utilisés uniquement lors de la synchronisation.

## Cloisonnement des builds

La récupération et la compilation d'un site exécutent du code issu de son dépôt (thème, templates et configuration Hugo…), que toute personne ayant accès au dépôt peut modifier. Elles tournent donc dans un sandbox systemd (`sandbox/run`), sous l'utilisateur `kelmscott-build`, sans droits :

- le build ne voit que le dossier de son site : les autres sites, les logs, `/home` (donc la clé privée et le jeton) sont masqués ;
- il ne peut écrire que dans le dossier de son site, ni gagner de privilèges (pas de sudo, ni de setuid) ;
- ses ressources sont limitées (4 Go de mémoire, 2 CPU, 30 minutes), et ses processus sont tués à la fin ;
- ses caches (Hugo…) sont propres au site : le dossier du site est son `HOME`.

La synchronisation, seule à recevoir les secrets déchiffrés, tourne hors sandbox, sous l'utilisateur du service, avec des scripts maîtrisés par Kelmscott.

L'utilisateur du service ne peut lancer en root que `/usr/local/sbin/kelmscott-sandbox`, qui vérifie ses arguments. Les scripts exécutés par root ou dans le sandbox sont des copies appartenant à root, installées par `bin/setup-sandbox` (lancé par `bin/setup` et `bin/update`).

```
/srv/kelmscott/
  sites/<université>/<site>/   écrit par le build, et son HOME (caches)
    repository/                dépôt git, compilé dans public/
  state/<université>/          écrit par le service, invisible depuis le sandbox
    <site>.log, .status, .lock
```

## Compilation

Kelmscott compile les sites lui-même, sans yarn ni script du thème, avec une **toolchain partagée** (`toolchain/`) : les dépendances npm du thème (PostCSS, cssnano, leaflet…) et pagefind, installées une seule fois avec npm par `bin/setup-sandbox` dans `/usr/local/lib/kelmscott/toolchain`, en lecture seule pour les builds.

`sandbox/compile` remplace le `node_modules` du site par un lien vers la toolchain, lance `hugo --minify`, puis pagefind depuis le dossier du thème : sa configuration (dossier du site, pages indexées, sélecteurs exclus) est dans le `pagefind.yml` du thème.

Il n'y a donc ni `node_modules`, ni cache npm par site, et aucun script npm ou du thème n'est exécuté.

Contraintes :

- le site utilise le thème Osuny dans `themes/osuny`, dans une version qui fournit `pagefind.yml` ;
- le site n'a pas d'autres dépendances npm que le thème : les sites qui en ont continuent d'être compilés par leur propre CI ;
- `toolchain/package.json` suit le `package.json` du thème : une dépendance ajoutée, retirée ou mise à jour dans le thème doit l'être aussi dans la toolchain (puis `npm install --package-lock-only` dans `toolchain/`).

## Synchronisation

Les scripts de synchronisation sont dans Kelmscott (`sync/`), et non dans les dépôts des sites : seul du code maîtrisé par Kelmscott a accès aux secrets déchiffrés.

Après une compilation réussie, Kelmscott lance `sync/<sync_method>` avec le chemin du dépôt, et uniquement les variables de la méthode choisie dans son environnement. Le dossier envoyé est toujours `public/` ; la publication est refusée s'il contient un lien symbolique. Aucun secret n'est écrit sur le disque. La sortie est ajoutée au log du site.

| Méthode | Outil | Variables |
|---------|-------|-----------|
| `dxfl` | [dxfl](https://git.deuxfleurs.fr/Deuxfleurs/dxfl) | `DXFL_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (onglet S3 du Guichet Deuxfleurs) |
| `rsync` | rsync sur SSH | `RSYNC_HOST`, `RSYNC_PORT` (22 par défaut), `RSYNC_USER`, `RSYNC_PATH`, `RSYNC_SSH_PRIVATE_KEY` |
| `sftp` | rclone | `SFTP_HOST`, `SFTP_PORT` (22 par défaut), `SFTP_USER`, `SFTP_PASSWORD`, `SFTP_PATH` |
| `s3` | rclone | `S3_BUCKET`, `S3_ENDPOINT` (vide pour AWS), `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

Pour `dxfl`, le fichier `deuxfleurs.toml` du dépôt (redirections, en-têtes) est pris en compte. Pour `rsync`, la clé publique de l'hôte distant est acceptée à la première connexion, puis vérifiée.
