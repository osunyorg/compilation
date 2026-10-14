require_relative 'publication/site'
require_relative 'publication/variables'
require_relative 'publication/sandbox'
require_relative 'publication/report'
require_relative 'publication/queue'

# Publication d'un site : récupération, compilation, contrôle de public/ et synchronisation, exécutées en arrière-plan
class Publication
  # Les variables arrivent telles que reçues de l'admin : les secrets sont déchiffrés au dernier moment,
  # en mémoire, pour la synchronisation
  def initialize(university, site, git_url, sync_method, variables)
    @site = Site.new(university, site)
    @git_url = git_url
    @sync_method = sync_method
    @variables = variables
    @sandbox = Sandbox.new(@site)
    @report = Report.new(@site)
  end

  def run
    site.lock do
      start
      fetched && compiled && publishable && synced && succeeded
    ensure
      report.finish
    end
  rescue StandardError => e
    error "#{e.class}: #{e.message}"
  end

  private

  attr_reader :site, :git_url, :sync_method, :variables, :sandbox, :report

  def start
    site.status = 'building'
    report.start
  end

  def fetched
    report.step('Récupération') { sandbox.fetch(git_url) } || error('Récupération du dépôt impossible')
  end

  def compiled
    report.step('Compilation') { sandbox.compile } || error('Échec de la compilation')
  end

  def publishable
    return error('Site compilé introuvable : public/ doit être un dossier') unless File.lstat(site.public_path).directory?
    return error('Site compilé incomplet : public/index.html manquant') unless File.file?(File.join(site.public_path, 'index.html'))
    forbidden = Dir.glob('**/*', File::FNM_DOTMATCH, base: site.public_path).reject do |path|
      %w[file directory].include?(File.lstat(File.join(site.public_path, path)).ftype)
    end
    forbidden.empty? || error("Fichiers interdits dans public (liens symboliques, fichiers spéciaux) : #{forbidden.join(', ')}")
  end

  def synced
    report.step('Synchronisation') { sync } || error('Échec de la synchronisation')
  end

  # Les secrets sont déchiffrés ici, au dernier moment, en mémoire
  def sync
    secrets = Variables.secrets(variables)
    sandbox.sync(sync_method, variables.merge(secrets), secrets.values)
  end

  def succeeded
    site.status = 'success'
  end

  def error(message)
    site.status = 'failure'
    site.append_log("\n#{message}\n")
    warn "[#{site}] #{message}"
    false
  end
end
