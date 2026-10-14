# Chargé par les scripts de bin/, lancés depuis la racine du dépôt.
# L'utilisateur du service est le propriétaire du dépôt : les scripts peuvent être lancés par un autre administrateur.
SERVICE_USER="$(stat -c %U .)"
SERVICE_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
# Par son chemin complet : sudo -u ne garde pas le PATH de l'utilisateur du service
MISE="$SERVICE_HOME/.local/bin/mise"

# Exécute une commande sous l'utilisateur du service, avec ses outils mise
as_service() {
  if [ "$(id -un)" = "$SERVICE_USER" ]; then
    "$MISE" exec -- "$@"
  else
    sudo -u "$SERVICE_USER" -H "$MISE" exec -- "$@"
  fi
}
