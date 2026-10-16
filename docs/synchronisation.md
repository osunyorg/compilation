# Synchronisation

Les scripts de synchronisation sont dans Kelmscott (`sync/`), et non dans les dépôts des sites : seul du code maîtrisé par Kelmscott a accès aux secrets déchiffrés.

rsync et ssh viennent des paquets Ubuntu, mis à jour par le système. rclone est installé avec mise, en version figée dans `bin/steps/tools`, car le paquet Ubuntu est ancien et ne reçoit pas de correctifs de sécurité.

Après une compilation réussie, Kelmscott lance `sync/<sync_method>` dans le sandbox, sous l'utilisateur `kelmscott-sync` (voir [Cloisonnement des builds](cloisonnement.md)), avec le chemin du dépôt, et uniquement les variables de la méthode choisie dans son environnement. Le dossier envoyé est toujours `public/` ; la publication est refusée s'il contient autre chose que des fichiers et des dossiers ordinaires (lien symbolique, FIFO…). Aucun secret n'est écrit sur le disque. La sortie est ajoutée au log du site, après masquage des secrets : chaque valeur secrète, et chaque ligne d'une clé SSH, y est remplacée par `[secret masqué]`.

## dxfl

Envoi vers Deuxfleurs avec [dxfl](https://git.deuxfleurs.fr/Deuxfleurs/dxfl). Le fichier `deuxfleurs.toml` du dépôt (redirections, en-têtes) est pris en compte.

dxfl est installé à part (`dxfl/`), en version figée avec ses dépendances, dans `/usr/local/lib/kelmscott/dxfl`, en lecture seule. Il est lancé par son chemin absolu : jamais avec `npx` dans le dépôt, dont le `.npmrc` et le `node_modules` sont contrôlés par le build. Pour le mettre à jour, changer sa version dans `dxfl/package.json`, lancer `dxfl/update` sur un poste de développement, puis commiter `package-lock.json`, comme pour les [dépendances de build](compilation.md#mise-à-jour-des-dépendances-de-build).

Variables, à récupérer dans l'onglet S3 du Guichet Deuxfleurs :

- `DXFL_BUCKET`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY` (secret)

## rsync

Copie incrémentale avec rsync sur SSH. La clé publique de l'hôte distant est acceptée à la première connexion, puis vérifiée.

Variables :

- `RSYNC_HOST`
- `RSYNC_PORT` (22 par défaut)
- `RSYNC_USER`
- `RSYNC_PATH`
- `RSYNC_SSH_PRIVATE_KEY` (secret)
- `RSYNC_BASTION_HOST` (optionnel, en cas d'utilisation de bastion SSH)
- `RSYNC_BASTION_PORT` (optionnel, 22 par défaut)
- `RSYNC_BASTION_USER` (optionnel)

## sftp

Envoi par SFTP avec mot de passe, via rclone.

Variables :

- `SFTP_HOST`
- `SFTP_PORT` (22 par défaut)
- `SFTP_USER`
- `SFTP_PASSWORD` (secret)
- `SFTP_PATH`

## s3

Envoi vers un bucket compatible S3 (AWS, Scaleway, OVH, Garage…), via rclone.

Variables :

- `S3_BUCKET`
- `S3_ENDPOINT` (vide pour AWS)
- `S3_REGION`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY` (secret)
