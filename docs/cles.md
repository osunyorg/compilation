# Clés de chiffrement

Les secrets de synchronisation des sites (mots de passe SFTP, clés AWS…) sont saisis dans l'admin Osuny, qui les chiffre immédiatement avec la **clé publique** de Kelmscott. Seul Kelmscott possède la **clé privée** permettant de les déchiffrer : l'admin ne stocke et ne transmet donc jamais de secret en clair.

Le chiffrement utilise les [sealed boxes de libsodium](https://doc.libsodium.org/public-key_cryptography/sealed_boxes) (Curve25519), via la gem `rbnacl`, des deux côtés.

En sens inverse, l'admin **signe** ses demandes avec sa propre clé privée ([Ed25519](https://doc.libsodium.org/public-key_cryptography/public-key_signatures)). Kelmscott ne détient que la clé publique correspondante : il peut vérifier qu'une demande vient de l'admin, mais personne ne peut en fabriquer une à partir de ce qui est stocké sur la machine.

## Création

### 1. Clé de signature de l'admin

Dans l'admin Osuny :

```bash
bin/rails app:kelmscott:signing_key
```

La tâche affiche, sans rien enregistrer :

- `KELMSCOTT_SIGNING_KEY`, à mettre dans la configuration de l'admin (`config/application.yml` ou variables d'environnement), jamais versionnée ni copiée sur Kelmscott ;
- la commande à lancer sur Kelmscott, avec la clé publique correspondante.

### 2. Clés de Kelmscott

Sur Kelmscott, la commande affichée à l'étape 1 :

```bash
~/kelmscott/bin/configure/keys <clé publique de signature de l'admin>
```

Le script crée la clé privée de Kelmscott si elle n'existe pas encore, et enregistre la clé publique de l'admin :

- `app/config/kelmscott.key` : la clé privée de Kelmscott (32 octets, en base 64), lisible uniquement par l'utilisateur du service ;
- `app/config/admin.pub` : la clé publique de signature de l'admin.

Ces fichiers ne sont pas versionnés. Le script peut être relancé sans risque : il ne remplace jamais la clé privée.

Il affiche `KELMSCOTT_PUBLIC_KEY`, à mettre dans la configuration de l'admin. Celle-ci contient alors :

```yaml
KELMSCOTT_URL: https://kelmscott.osuny.org
KELMSCOTT_PUBLIC_KEY: <affichée par configure/keys>
KELMSCOTT_SIGNING_KEY: <affichée par app:kelmscott:signing_key>
```

`KELMSCOTT_URL` doit être en `https://`, y compris en développement : l'admin refuse d'envoyer une demande autrement, car les paramètres non secrets (hôtes, utilisateurs, chemins) ne sont protégés que par TLS pendant le transport.

## Sauvegarde et renouvellement

La clé privée de Kelmscott doit être sauvegardée hors de la machine (gestionnaire de mots de passe). Si elle est perdue ou renouvelée, tous les secrets enregistrés dans l'admin deviennent indéchiffrables et doivent être ressaisis, site par site, après mise à jour de `KELMSCOTT_PUBLIC_KEY`.

Pour renouveler la paire de clés de Kelmscott :

```bash
rm ~/kelmscott/app/config/kelmscott.key
~/kelmscott/bin/configure/keys
```

La clé de signature de l'admin n'a pas besoin d'être sauvegardée : elle ne protège aucun secret enregistré. Si elle est perdue ou compromise, elle se renouvelle sans conséquence sur les secrets, en refaisant les étapes 1 et 2.
