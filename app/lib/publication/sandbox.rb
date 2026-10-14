require 'base64'
require 'open3'

class Publication
  # Lance les étapes d'une publication par kelmscott-sandbox (sandbox/run), et écrit leur sortie au log du site.
  # La récupération et la compilation, qui exécutent du code du dépôt, tournent sous kelmscott-build ;
  # la synchronisation, qui reçoit les secrets, sous kelmscott-sync.
  class Sandbox
    PATH = '/usr/local/sbin/kelmscott-sandbox'

    def initialize(site)
      @site = site
    end

    # sandbox/fetch et sandbox/compile exécutent du code du dépôt, sans les secrets
    def fetch(git_url)
      run('fetch', git_url)
    end

    def compile
      run('compile')
    end

    # Les variables passent par l'entrée standard : ni par les arguments (visibles dans ps),
    # ni par l'environnement de l'unité systemd (visible dans systemctl show).
    # Les secrets sont masqués dans la sortie écrite au log.
    def sync(sync_method, environment, secrets)
      run('sync', sync_method, input: encode(environment), secrets: secrets)
    end

    private

    attr_reader :site

    def run(command, *arguments, **options)
      execute('sudo', '--non-interactive', PATH, command, site.university, site.name, *arguments, **options)
    end

    # Une variable par ligne, NOM=valeur en base 64, lue par sandbox/sync
    def encode(environment)
      environment.map { |name, value| "#{name}=#{Base64.strict_encode64(value)}\n" }.join
    end

    # Sans entrée, la sortie va directement au log. Avec une entrée (la synchronisation), elle est relue ligne par ligne
    # pour masquer les secrets avant d'être écrite.
    def execute(*command, input: nil, secrets: [])
      log_path = site.state_file('log')
      return system(*command, out: [log_path, 'a'], err: [:child, :out]) if input.nil?
      Open3.popen2e(*command) do |stdin, output, process|
        begin
          stdin.write(input)
        rescue Errno::EPIPE
          # Le processus s'est arrêté sans tout lire : son code de sortie le dit
        end
        stdin.close
        File.open(log_path, 'ab') do |log|
          output.each_line { |line| log.write(mask(line, secrets)) }
        end
        process.value.success?
      end
    end

    # Chaque secret, et chaque ligne d'un secret sur plusieurs lignes (clé SSH), est remplacé dans le texte.
    # En octets : la sortie des outils n'est pas forcément de l'UTF-8 valide.
    def mask(text, secrets)
      parts = secrets.flat_map { |secret| [secret, *secret.lines] }.map { |part| part.strip.b }.reject { |part| part.length < 4 }
      parts.uniq.sort_by(&:length).reverse.reduce(text.b) { |masked, part| masked.gsub(part, '[secret masqué]'.b) }
    end
  end
end
