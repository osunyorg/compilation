# Chargé par les scripts de bin/, lancés depuis la racine du dépôt.
# L'utilisateur du service est le propriétaire du dépôt : les scripts peuvent être lancés par un autre administrateur.
SERVICE_USER="$(stat -c %U .)"
SERVICE_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"

# Exécute une commande sous l'utilisateur du service, avec ses outils mise
as_service() {
  if [ "$(id -un)" = "$SERVICE_USER" ]; then
    "$SERVICE_HOME/.local/bin/mise" exec -- "$@"
  else
    sudo -u "$SERVICE_USER" -H "$SERVICE_HOME/.local/bin/mise" exec -- "$@"
  fi
}
