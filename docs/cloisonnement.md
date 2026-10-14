# Cloisonnement des builds

La récupération et la compilation d'un site exécutent du code issu de son dépôt (thème, templates et configuration Hugo…), que toute personne ayant accès au dépôt peut modifier. Elles tournent donc dans un sandbox systemd (`sandbox/run`), sous l'utilisateur `kelmscott-build`, sans droits :

- le build ne voit que le dossier de son site : les autres sites, les logs, `/home` (donc les clés) sont masqués ;
- il ne peut écrire que dans le dossier de son site, ni gagner de privilèges (pas de sudo, ni de setuid) ;
- ses ressources sont limitées (4 Go de mémoire, 2 CPU, 30 minutes), et ses processus sont tués à la fin ;
- ses caches (Hugo…) sont propres au site : le dossier du site est son `HOME`.

La synchronisation, seule à recevoir les secrets déchiffrés, tourne dans le même sandbox, sous un autre utilisateur, `kelmscott-sync`, avec des scripts maîtrisés par Kelmscott :

- elle ne voit que le dépôt de son site, en lecture seule, et `/home` (donc la clé privée de Kelmscott) est masqué : un outil de synchronisation compromis n'obtient que les variables du site en cours ;
- les variables arrivent sur son entrée standard (`sandbox/sync`), jamais dans ses arguments (visibles dans `ps`) ni dans l'environnement de l'unité systemd (visible dans `systemctl show`) ;
- ses ressources et sa durée sont limitées comme pour le build : une synchronisation bloquée est arrêtée au bout de 30 minutes ;
- son `HOME` (`/var/lib/kelmscott-sync`) garde les clés des hôtes ssh d'une publication à l'autre.

L'utilisateur du service ne peut lancer en root que `/usr/local/sbin/kelmscott-sandbox`, qui vérifie ses arguments. Les scripts exécutés par root ou dans le sandbox sont des copies appartenant à root, installées par `bin/steps/sandbox` (lancé par `bin/setup` et `bin/update`).

```
/srv/kelmscott/
  sites/<université>/<site>/   écrit par le build, et son HOME (caches)
    repository/                dépôt git, compilé dans public/
  state/                       écrit par le service, invisible depuis les sandbox
    <université>/<site>.log, .status, .size, .lock
    .queue/<université>/<site>.json   demande en attente, secrets chiffrés
    .signatures/               signatures déjà reçues (rejeu)
```
