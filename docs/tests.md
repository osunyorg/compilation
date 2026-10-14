# Tests

```bash
cd app
bundle install
bundle exec rake test
```

Les tests couvrent l'interface web, les demandes de l'admin (signature, validation, déchiffrement), le badge, et le déroulement d'une publication avec un sandbox et une synchronisation simulés. Le sandbox lui-même ne tourne que sur Linux avec systemd : il se vérifie sur la machine, avec le [protocole de vérification](verification.md).
