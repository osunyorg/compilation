# Protocole de vérification

À dérouler après l'installation et après toute modification du sandbox. Dans les commandes, `DOMAINE` est le domaine de la VM.

## 1. Services

```bash
systemctl is-active kelmscott-puma nginx
id kelmscott-build
ls -l /usr/local/sbin/kelmscott-sandbox /usr/local/lib/kelmscott /etc/sudoers.d/kelmscott
```

Attendu : deux fois `active`, l'utilisateur `kelmscott-build` existe, et les fichiers appartiennent à `root`.

## 2. Sandbox

```bash
sudo -n /usr/local/sbin/kelmscott-sandbox
sudo -n /usr/local/sbin/kelmscott-sandbox compile ../.. site
sudo -n /usr/local/sbin/kelmscott-sandbox fetch test site file:///etc
```

Attendu : `commande inconnue`, `université invalide`, puis `URL invalide`, sans demande de mot de passe.

## 3. HTTP

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://DOMAINE/
curl -s -w ' %{http_code}\n' -X POST https://DOMAINE/test/site -H 'Content-Type: application/json' -d '{}'
curl -s https://DOMAINE/test/inconnu/badge.svg | grep -o '<title>[^<]*'
```

Attendu : `200`, puis `Unauthorized 401`, puis `Kelmscott : inconnu`.

## 4. Isolation

Créer un dépôt de test public (par exemple `kelmscott-canary`) qui tente de sortir du sandbox. Le seul code du dépôt que Kelmscott exécute est celui que Hugo confie à Node, comme `postcss.config.js` : le canary s'y loge, et lève la restriction de Node dans sa configuration Hugo, comme le ferait un dépôt malveillant.

`hugo.toml` :

```toml
baseURL = "https://example.org/"
disableKinds = ["taxonomy", "term", "RSS", "sitemap", "robotsTXT", "404"]

[security.node.permissions]
allowChildProcess = ["postcss"]
```

`layouts/index.html` :

```html
<html><body>{{ with resources.Get "canary.css" | postCSS }}{{ .RelPermalink }}{{ end }}</body></html>
```

`assets/canary.css` :

```css
body {}
```

`postcss.config.js` :

```js
require('child_process').execSync('sh canary.sh > canary.txt 2>&1')
module.exports = { plugins: [] }
```

`themes/osuny/pagefind.yml` :

```yaml
site: ../../public
```

`canary.sh` :

```sh
echo "== utilisateur"; id
echo "== clé privée"; cat /home/*/kelmscott/app/config/kelmscott.key
echo "== sites visibles"; ls /srv/kelmscott/sites
echo "== logs des autres sites"; ls /srv/kelmscott/state
echo "== sudo"; sudo -n true
echo "== écriture hors du site"; touch /etc/canary /srv/kelmscott/canary
echo "== écriture dans /tmp"; touch /tmp/canary && echo "ok (privé)"
echo "== toolchain en lecture seule"; touch node_modules/canary
echo "== réseau"; curl -sI https://registry.npmjs.org | head -1
```

Lancer sa publication depuis l'admin Osuny, seul détenteur de la clé de signature, dans une console Rails (`bin/rails console`) :

```ruby
path = "/test/canary"
body = { git_url: "https://github.com/<compte>/kelmscott-canary.git", sync_method: "dxfl", variables: { DXFL_BUCKET: "test" } }.to_json
timestamp = Time.now.to_i.to_s
signing_key = RbNaCl::SigningKey.new(Base64.strict_decode64(ENV["KELMSCOTT_SIGNING_KEY"]))
signature = Base64.strict_encode64(signing_key.sign("#{timestamp}\nPOST #{path}\n#{body}".b))
response = Faraday.post("#{ENV["KELMSCOTT_URL"]}#{path}", body, "Content-Type" => "application/json", "X-Kelmscott-Timestamp" => timestamp, "X-Kelmscott-Signature" => signature)
response.status
```

Attendu : `202`.

Puis lire le résultat sur la VM, écrit dans le dépôt :

```bash
sleep 60
cat /srv/kelmscott/sites/test/canary/repository/canary.txt
```

Attendu :

| Test | Résultat attendu |
|---|---|
| utilisateur | `kelmscott-build` |
| clé privée | `No such file or directory` |
| sites visibles | `test` seulement |
| logs des autres sites | `No such file or directory` |
| sudo | refusé (`no new privileges`) |
| écriture hors du site | `Read-only file system` |
| écriture dans /tmp | `ok (privé)` |
| toolchain en lecture seule | `Read-only file system` |
| réseau | `HTTP/2 200` |

La synchronisation échoue ensuite, faute de clés dxfl : c'est normal, et le badge de `test/canary` passe à `échec`, ce qui vérifie que les échecs remontent bien du sandbox.

## 5. Publication réelle

Activer Kelmscott sur un site dans l'admin Osuny et le publier. Attendu : le log du site (page `https://DOMAINE/<université>/<dépôt>`) se termine par les durées et le poids, le badge passe à `succès`, et le site est en ligne.

## 6. Nettoyage

```bash
sudo rm -rf /srv/kelmscott/sites/test /srv/kelmscott/state/test
```
