# Mise à jour

```bash
~/kelmscott/bin/update
```

`bin/update` récupère le code, puis se relance dans sa nouvelle version pour installer les versions des outils (`bin/steps/tools`), les gems et les copies root du sandbox, et redémarre le service. Pour changer la version d'un outil (Hugo, Node, rclone…), il suffit de la modifier dans `bin/steps/tools`.
