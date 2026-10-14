# Clés de chiffrement

Les secrets de synchronisation des sites (mots de passe SFTP, clés AWS…) sont saisis dans l'admin Osuny, qui les chiffre immédiatement avec la **clé publique** de Kelmscott. Seul Kelmscott possède la **clé privée** permettant de les déchiffrer : l'admin ne stocke et ne transmet donc jamais de secret en clair.

Le chiffrement utilise les [sealed boxes de libsodium](https://doc.libsodium.org/public-key_cryptography/sealed_boxes) (Curve25519), via la gem `rbnacl`, des deux côtés.

En sens inverse, l'admin **signe** ses demandes avec sa propre clé privée ([Ed25519](https://doc.libsodium.org/public-key_cryptography/public-key_signatures)). Kelmscott ne détient que la clé publique correspondante : il peut vérifier qu'une demande vient de l'admin, mais personne ne peut en fabriquer une à partir de ce qui est stocké sur la machine.

## Création

Dans l'admin Osuny, générer la clé de signature :

```bash
bin/rails runner 'k = RbNaCl::SigningKey.generate; puts "KELMSCOTT_SIGNING_KEY: #{Base64.strict_encode64(k.to_bytes)}"; puts "Clé publique : #{Base64.strict_encode64(k.verify_key.to_bytes)}"'
```

Puis sur Kelmscott, avec la clé publique affichée :

```bash
cd kelmscott
bin/setup-keys <clé publique de signature de l'admin>
```

Le script crée la clé privée de Kelmscott si elle n'existe pas encore, et enregistre la clé publique de l'admin :

- `app/config/kelmscott.key` : la clé privée de Kelmscott (32 octets, en base 64), lisible uniquement par l'utilisateur courant ;
- `app/config/admin.pub` : la clé publique de signature de l'admin.

Ces fichiers ne sont pas versionnés. Le script affiche ensuite la clé publique de Kelmscott. La configuration de l'admin Osuny (`config/application.yml` ou variables d'environnement) contient alors :

```yaml
KELMSCOTT_URL: https://kelmscott.osuny.org
KELMSCOTT_PUBLIC_KEY: <clé publique de Kelmscott>
KELMSCOTT_SIGNING_KEY: <clé de signature de l'admin>
```

Le script peut être relancé sans risque pour réafficher la clé publique : il ne remplace jamais la clé privée.

`KELMSCOTT_URL` doit être en `https://`, y compris en développement : l'admin refuse d'envoyer une demande autrement, car les paramètres non secrets (hôtes, utilisateurs, chemins) ne sont protégés que par TLS pendant le transport.

## Sauvegarde et renouvellement

La clé privée doit être sauvegardée hors de la machine (gestionnaire de mots de passe). Si elle est perdue ou renouvelée, tous les secrets enregistrés dans l'admin deviennent indéchiffrables et doivent être ressaisis, site par site, après mise à jour de `KELMSCOTT_PUBLIC_KEY`.

Pour renouveler la paire de clés :

```bash
rm app/config/kelmscott.key
bin/setup-keys
bin/restart
```

La clé de signature de l'admin se renouvelle sans conséquence sur les secrets : générer une nouvelle clé dans l'admin, mettre à jour `KELMSCOTT_SIGNING_KEY`, puis lancer `bin/setup-keys <nouvelle clé publique>` et `bin/restart` sur Kelmscott.
