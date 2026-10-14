# Requêtes de l'admin Osuny

L'admin demande une compilation avec une requête `POST` sur `/:university/:site`. `university` est l'identifiant de l'université dans l'admin, `site` le nom du dépôt du site (sans l'organisation). Le même chemin sert pour le badge (`/:university/:site/badge.svg`) :

```bash
curl -X POST https://kelmscott.osuny.org/noesya/noesya-www \
  -H "X-Kelmscott-Timestamp: 1791990000" \
  -H "X-Kelmscott-Signature: <signature, en base 64>" \
  -H "Content-Type: application/json" \
  -d '{
    "git_url": "https://github.com/noesya/noesya-www.git",
    "sync_method": "s3",
    "variables": {
      "S3_BUCKET": "www.noesya.coop",
      "S3_REGION": "fr-par",
      "AWS_ACCESS_KEY_ID": "SCW...",
      "AWS_SECRET_ACCESS_KEY": "<valeur chiffrée, en base 64>"
    }
  }'
```

- la signature porte sur les octets de `"<horodatage>\nPOST <chemin>\n<corps>"`, signée avec la clé de l'admin (Ed25519) ; une demande de plus de 5 minutes est refusée, et une même demande n'est acceptée qu'une fois (pas de rejeu) ;
- `git_url` doit être une URL `https://`, sans identifiants, sur une forge autorisée (`GIT_HOSTS` dans `app/lib/helpers.rb` : github.com, gitlab.com) ;
- `sync_method` vaut `sftp`, `dxfl`, `rsync` ou `s3` ;
- `variables` n'accepte que les clés prévues pour la méthode choisie (même liste blanche que `Communication::Website::Variable` dans l'admin) ;
- les secrets (`SFTP_PASSWORD`, `RSYNC_SSH_PRIVATE_KEY`, `AWS_SECRET_ACCESS_KEY`) sont envoyés tels que stockés par l'admin, chiffrés : Kelmscott les déchiffre en mémoire et ne les écrit nulle part.

Réponses :

| Code | Signification |
|------|---------------|
| 202 | Demande acceptée, le clone/pull, la compilation puis la synchronisation s'exécutent en arrière-plan |
| 400 | Paramètres invalides, ou secret impossible à déchiffrer (mauvaise clé publique dans l'admin) |
| 401 | Signature absente, invalide ou expirée |
| 409 | Demande déjà reçue (rejeu) |
| 415 | Le corps n'est pas en `application/json` |
| 503 | Les clés n'ont pas été configurées (`bin/configure/keys`), ou trop de publications en cours : l'admin réessaie plus tard |

Les compilations d'un même site sont exécutées l'une après l'autre, et au plus deux publications tournent en même temps par processus Puma (`Publication::MAX_RUNNING`). Les secrets ne sont pas transmis à la compilation (Hugo et le thème exécutent du code issu du dépôt) ; ils sont utilisés uniquement lors de la synchronisation.
