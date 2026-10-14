require 'base64'
require 'rbnacl'

module Helpers
  # Générés par bin/setup-keys, jamais versionnés
  PRIVATE_KEY_PATH = File.expand_path('../config/kelmscott.key', __dir__)
  TOKEN_PATH = File.expand_path('../config/kelmscott.token', __dir__)

  def directories_in(path)
    return [] unless File.directory?(path)
    Dir.children(path)
       .select { |name| File.directory?(File.join(path, name)) }
       .sort
  end

  # Lettres, chiffres, '_', '-' et '.', sans commencer par '.' (exclut '.', '..' et les dossiers cachés)
  def valid_name?(name)
    name.match?(/\A[\w-][\w.-]*\z/)
  end

  def get_logs(university, site)
    path = File.join(Publication::STATE_PATH, university, "#{site}.log")
    return unless File.exist? path
    # Explicite : sous systemd, sans LANG, Ruby lirait le fichier en US-ASCII
    File.read(path, encoding: 'UTF-8').scrub
  end

  # État de la dernière publication, écrit par Publication
  def get_status(university, site)
    path = File.join(Publication::STATE_PATH, university, "#{site}.status")
    File.exist?(path) ? File.read(path).strip : 'unknown'
  end

  # Texte et couleur du badge
  def badge(status)
    case status
    when 'building' then ['en cours', '#dfb317']
    when 'success' then ['succès', '#4c1']
    when 'failure' then ['échec', '#e05d44']
    else ['inconnu', '#9f9f9f']
    end
  end

  def read_config(path)
    File.read(path).strip if File.exist?(path)
  end

  def configured?
    File.exist?(PRIVATE_KEY_PATH) && File.exist?(TOKEN_PATH)
  end

  def authorized?
    token = read_config(TOKEN_PATH)
    return false if token.to_s.empty?
    provided = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
    Rack::Utils.secure_compare(token, provided)
  end

  # Les secrets sont chiffrés par l'admin avec la clé publique (sealed box libsodium)
  def decrypt(value)
    private_key = RbNaCl::PrivateKey.new(Base64.strict_decode64(read_config(PRIVATE_KEY_PATH)))
    RbNaCl::Boxes::Sealed.from_private_key(private_key).decrypt(Base64.strict_decode64(value))
  end
end
