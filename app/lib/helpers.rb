require 'base64'
require 'rbnacl'
require 'uri'

module Helpers
  # Générés par bin/setup-keys, jamais versionnés
  PRIVATE_KEY_PATH = File.expand_path('../config/kelmscott.key', __dir__)
  # Clé publique de signature de l'admin Osuny, pour vérifier l'origine des demandes
  ADMIN_KEY_PATH = File.expand_path('../config/admin.pub', __dir__)
  # Au-delà, une demande signée est refusée, pour limiter le rejeu
  SIGNATURE_MAX_AGE = 300
  # Forges depuis lesquelles un dépôt peut être récupéré
  GIT_HOSTS = %w[github.com gitlab.com].freeze

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

  # Somme des espaces disque enregistrés à la fin de chaque publication
  def used_space
    Dir[File.join(Publication::STATE_PATH, '*', '*.size')].sum { |path| File.read(path).to_i }
  end

  # Espace libre et total du disque de Kelmscott, en octets
  def disk_space
    _, line = IO.popen(['df', '-Pk', Publication::STATE_PATH], err: File::NULL, &:readlines)
    return [0, 0] unless line
    total, _used, free = line.split[1..3].map { |kilobytes| kilobytes.to_i * 1024 }
    [free, total]
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

  # Favicon de la vue d'un site : un rond de la couleur de son badge
  def status_favicon(status)
    _, color = badge(status)
    svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><circle cx='8' cy='8' r='8' fill='#{color}'/></svg>"
    "data:image/svg+xml,#{ERB::Util.url_encode(svg)}"
  end

  def read_config(path)
    File.read(path).strip if File.exist?(path)
  end

  def configured?
    File.exist?(PRIVATE_KEY_PATH) && File.exist?(ADMIN_KEY_PATH)
  end

  # La demande est signée par l'admin (Ed25519) : horodatage, méthode, chemin et corps.
  # Kelmscott n'a que la clé publique, il ne peut donc pas fabriquer de demande valide.
  def signed?(body)
    timestamp = request.env['HTTP_X_KELMSCOTT_TIMESTAMP'].to_s
    return false unless timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= SIGNATURE_MAX_AGE
    signature = Base64.strict_decode64(request.env['HTTP_X_KELMSCOTT_SIGNATURE'].to_s)
    verify_key = RbNaCl::VerifyKey.new(Base64.strict_decode64(read_config(ADMIN_KEY_PATH)))
    verify_key.verify(signature, "#{timestamp}\n#{request.request_method} #{request.path_info}\n#{body}")
  rescue ArgumentError, RbNaCl::CryptoError
    false
  end

  def valid_git_url?(git_url)
    uri = URI.parse(git_url)
    uri.scheme == 'https' && GIT_HOSTS.include?(uri.host) && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  # Les secrets sont chiffrés par l'admin avec la clé publique (sealed box libsodium)
  def decrypt(value)
    private_key = RbNaCl::PrivateKey.new(Base64.strict_decode64(read_config(PRIVATE_KEY_PATH)))
    RbNaCl::Boxes::Sealed.from_private_key(private_key).decrypt(Base64.strict_decode64(value))
  end
end
