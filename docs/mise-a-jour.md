# Mise à jour

```bash
cd kelmscott
git pull
bin/update
bin/restart
```

`bin/update` réinstalle les copies root du sandbox. Lors de la première mise à jour qui l'ajoute, lancer aussi `bin/setup-sandbox` à la main : bash continue d'exécuter l'ancienne version de `bin/update`, remplacée pendant le `git pull`.
