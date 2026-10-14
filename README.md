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

## Documentation

- [Installation](docs/installation.md)
- [Protocole de vérification](docs/verification.md)
- [Mise à jour](docs/mise-a-jour.md)
- [Tests](docs/tests.md)
- [Clés de chiffrement](docs/cles.md)
- [Requêtes de l'admin Osuny](docs/requetes.md)
- [Cloisonnement des builds](docs/cloisonnement.md)
- [Compilation](docs/compilation.md)
- [Synchronisation](docs/synchronisation.md)
