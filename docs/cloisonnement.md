# Cloisonnement des builds

La récupération et la compilation d'un site exécutent du code issu de son dépôt (thème, templates et configuration Hugo…), que toute personne ayant accès au dépôt peut modifier. Elles tournent donc dans un sandbox systemd (`sandbox/run`), sous l'utilisateur `kelmscott-build`, sans droits :

- le build ne voit que le dossier de son site : les autres sites, les logs, `/home` (donc les clés) sont masqués ;
- il ne peut écrire que dans le dossier de son site, ni gagner de privilèges (pas de sudo, ni de setuid) ;
- ses ressources sont limitées (4 Go de mémoire, 2 CPU, 30 minutes), et ses processus sont tués à la fin ;
- ses caches (Hugo…) sont propres au site : le dossier du site est son `HOME`.

La synchronisation, seule à recevoir les secrets déchiffrés, tourne hors sandbox, sous l'utilisateur du service, avec des scripts maîtrisés par Kelmscott.

L'utilisateur du service ne peut lancer en root que `/usr/local/sbin/kelmscott-sandbox`, qui vérifie ses arguments. Les scripts exécutés par root ou dans le sandbox sont des copies appartenant à root, installées par `bin/steps/sandbox` (lancé par `bin/setup` et `bin/update`).

```
/srv/kelmscott/
  sites/<université>/<site>/   écrit par le build, et son HOME (caches)
    repository/                dépôt git, compilé dans public/
  state/<université>/          écrit par le service, invisible depuis le sandbox
    <site>.log, .status, .size, .lock
```
