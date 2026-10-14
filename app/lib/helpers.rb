require 'base64'
require 'digest'
require 'fileutils'
require 'rbnacl'
require 'uri'

module Helpers
  # Clé publique de signature de l'admin Osuny, pour vérifier l'origine des demandes (bin/configure/keys)
  ADMIN_KEY_PATH = File.expand_path('../config/admin.pub', __dir__)
  # Au-delà, une demande signée est refusée, pour limiter le rejeu
  SIGNATURE_MAX_AGE = 300
  # Forges depuis lesquelles un dépôt peut être récupéré
  GIT_HOSTS = %w[
    github.com
    gitlab.com
    git.osuny.org
    forge.osuny.org
    gitlab.osuny.org
    gitlab.ecedi.fr
    gitlab.huma-num.fr
  ].freeze

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

  # Somme des espaces disque enregistrés à la fin de chaque publication
  def used_space
    Dir[File.join(Publication::Site::STATE_PATH, '*', '*.size')].sum { |path| File.read(path).to_i }
  end

  # Espace libre et total du disque de Kelmscott, en octets
  def disk_space
    _, line = IO.popen(['df', '-Pk', Publication::Site::STATE_PATH], err: File::NULL, &:readlines)
    return [0, 0] unless line
    total, _used, free = line.split[1..3].map { |kilobytes| kilobytes.to_i * 1024 }
    [free, total]
  end

  # Texte et couleur du badge
  def badge(status)
    case status
    when 'queued' then ['en attente', '#007ec6']
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
    File.exist?(Publication::Variables::PRIVATE_KEY_PATH) && File.exist?(ADMIN_KEY_PATH)
  end

  # La demande est signée par l'admin (Ed25519) : horodatage, méthode, chemin et corps.
  # Kelmscott n'a que la clé publique, il ne peut donc pas fabriquer de demande valide.
  def signed?(body)
    timestamp = request.env['HTTP_X_KELMSCOTT_TIMESTAMP'].to_s
    return false unless timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= SIGNATURE_MAX_AGE
    signature = Base64.strict_decode64(request.env['HTTP_X_KELMSCOTT_SIGNATURE'].to_s)
    verify_key = RbNaCl::VerifyKey.new(Base64.strict_decode64(read_config(ADMIN_KEY_PATH)))
    verify_key.verify(signature, "#{timestamp}\n#{request.request_method} #{request.path_info}\n#{body}".b)
  rescue ArgumentError, RbNaCl::CryptoError
    false
  end

  # Une signature n'est acceptée qu'une fois : une demande interceptée ne peut pas être rejouée.
  # Ed25519 est déterministe, une même demande donne la même signature ; une nouvelle demande a un autre horodatage.
  # Un fichier par signature, créé de façon atomique : valable entre les processus Puma.
  def first_use?
    path = File.join(Publication::Site::STATE_PATH, '.signatures')
    FileUtils.mkdir_p(path)
    Dir.glob(File.join(path, '*')).each do |file|
      File.delete(file) if Time.now - File.mtime(file) > 2 * SIGNATURE_MAX_AGE
    rescue Errno::ENOENT
      # Déjà supprimé par un autre processus
    end
    signature = request.env['HTTP_X_KELMSCOTT_SIGNATURE'].to_s
    File.open(File.join(path, Digest::SHA256.hexdigest(signature)), File::CREAT | File::EXCL | File::WRONLY).close
    true
  rescue Errno::EEXIST
    false
  end

  def valid_git_url?(git_url)
    uri = URI.parse(git_url)
    uri.scheme == 'https' && GIT_HOSTS.include?(uri.host) && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end
end
