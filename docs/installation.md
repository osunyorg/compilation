# Installation d'une VM

## Prérequis

- Une VM **Ubuntu 24.04 LTS** neuve, avec une IP fixe : les hébergeurs des sites peuvent la mettre en liste blanche.
- Un accès SSH avec l'utilisateur `ubuntu`, qui a les droits sudo.
- Un nom de domaine (par exemple `kelmscott.osuny.org`) dont l'enregistrement DNS pointe vers l'IP de la VM.
- De l'espace disque : chaque site garde son dépôt (sources, historique git) et sa compilation, soit quelques dizaines de Mo par site.

## 1. Système et pare-feu

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git ufw
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
```

## 2. Kelmscott

Le dépôt doit être cloné dans `~/kelmscott` : le service systemd et la configuration nginx utilisent ce chemin.

```bash
cd ~
git clone https://github.com/osunyorg/kelmscott.git
cd kelmscott
bin/setup
```

`bin/setup` installe :

- les paquets système (compilation de Ruby, libsodium, rsync, rclone, nginx) ;
- Ruby, Node et Hugo, via mise ;
- l'application Sinatra, nginx en reverse proxy, et le service `kelmscott-puma` ;
- le sandbox des builds (`bin/setup-sandbox`, voir [Cloisonnement des builds](cloisonnement.md)).

Il faut ensuite ouvrir une nouvelle session SSH, pour que mise soit actif dans le shell.

## 3. Domaine et HTTPS

Remplacer `server_name` par le domaine de la VM dans `/etc/nginx/sites-available/kelmscott.conf`, puis :

```bash
sudo systemctl reload nginx
bin/setup-ssl
```

## 4. Clés de chiffrement

```bash
bin/setup-keys <clé publique de signature de l'admin>
```

Reporter la clé publique affichée dans la configuration de l'admin Osuny, et sauvegarder la clé privée hors de la machine (voir [Clés de chiffrement](cles.md)).

## 5. Démarrage

```bash
bin/start
```

## 6. Restriction de sudo (recommandé)

Sur les images cloud, `ubuntu` a généralement un sudo complet sans mot de passe. Les builds n'y ont pas accès (ils tournent sous `kelmscott-build`), mais si le service était compromis, il obtiendrait root. Une fois l'installation terminée, on peut ne lui laisser que le sandbox et le redémarrage du service, en remplaçant la ligne `ubuntu` de `/etc/sudoers.d/90-cloud-init-users` par :

```
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl restart kelmscott-puma.service, /usr/bin/systemctl start kelmscott-puma.service
```

`bin/setup` et `bin/update` ont alors besoin d'un autre compte administrateur. Faire la modification avec `sudo visudo -f /etc/sudoers.d/90-cloud-init-users`, en gardant une deuxième session SSH ouverte pour ne pas se retrouver bloqué.
