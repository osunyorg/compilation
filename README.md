# Kelmscott

![Kelmscott Press](kelmscott-press.jpg)

Ce référentiel doit être cloné sur la machine Kelmscott.

## Installation

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/osunyorg/kelmscott.git compilation
cd compilation
bin/setup
bin/setup-keys
bin/start
```

Une fois le domaine pointé, exécuter `bin/setup-ssl`

## Mise à jour

```bash
cd compilation
git pull
bin/update
bin/restart
```

## Génération du certificat SSL

```bash
sudo certbot --nginx
```

## Clés de chiffrement

Les secrets de synchronisation des sites (mots de passe SFTP, clés AWS…) sont saisis dans l'admin Osuny, qui les chiffre immédiatement avec la **clé publique** de Kelmscott. Seul Kelmscott possède la **clé privée** permettant de les déchiffrer : l'admin ne stocke et ne transmet donc jamais de secret en clair.

Le chiffrement utilise les [sealed boxes de libsodium](https://doc.libsodium.org/public-key_cryptography/sealed_boxes) (Curve25519), via la gem `rbnacl`, des deux côtés.

En plus de la paire de clés, un **jeton** partagé authentifie les requêtes de l'admin vers Kelmscott.

### Création

```bash
cd compilation
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
curl -X POST https://compilation.osuny.org/noesya/noesya-www \
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

Les compilations d'un même site sont exécutées l'une après l'autre. Les secrets ne sont pas transmis à la compilation (`yarn install` exécute du code issu du dépôt) ; ils sont utilisés uniquement lors de la synchronisation.

## Synchronisation

Les scripts de synchronisation sont dans Kelmscott (`bin/sync`), et non dans les dépôts des sites : seul du code maîtrisé par Kelmscott a accès aux secrets déchiffrés.

Après une compilation réussie, Kelmscott lance `bin/sync/<sync_method>` avec le chemin du dépôt, et uniquement les variables de la méthode choisie dans son environnement. Le dossier envoyé est toujours `public/`. Les liens symboliques sont ignorés et aucun secret n'est écrit sur le disque. La sortie est ajoutée au `log.txt` du site.

| Méthode | Outil | Variables |
|---------|-------|-----------|
| `dxfl` | [dxfl](https://git.deuxfleurs.fr/Deuxfleurs/dxfl) | `DXFL_WEBSITE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (onglet S3 du Guichet Deuxfleurs) |
| `rsync` | rsync sur SSH | `RSYNC_HOST`, `RSYNC_PORT` (22 par défaut), `RSYNC_USER`, `RSYNC_PATH`, `RSYNC_SSH_PRIVATE_KEY` |
| `sftp` | rclone | `SFTP_HOST`, `SFTP_PORT` (22 par défaut), `SFTP_USER`, `SFTP_PASSWORD`, `SFTP_PATH` |
| `s3` | rclone | `S3_BUCKET`, `S3_ENDPOINT` (vide pour AWS), `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

Pour `dxfl`, le fichier `deuxfleurs.toml` du dépôt (redirections, en-têtes) est pris en compte. Pour `rsync`, la clé publique de l'hôte distant est acceptée à la première connexion, puis vérifiée.
