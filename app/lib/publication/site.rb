require 'fileutils'

class Publication
  # Un site sur le disque de Kelmscott : son dossier, écrit par le build,
  # et son état (log, statut, poids, verrou), écrit par le service
  class Site
    # Un dossier par site, écrit par le build
    SITES_PATH = '/srv/kelmscott/sites'
    # Logs, statuts et verrous, écrits par le service, invisibles depuis les sandbox
    STATE_PATH = '/srv/kelmscott/state'

    attr_reader :university, :name

    def initialize(university, name)
      @university = university
      @name = name
    end

    def to_s
      "#{university}/#{name}"
    end

    def path
      File.join(SITES_PATH, university, name)
    end

    def repository_path
      File.join(path, 'repository')
    end

    def public_path
      File.join(repository_path, 'public')
    end

    # Fichier d'état : log, status, size ou lock
    def state_file(extension)
      File.join(STATE_PATH, university, "#{name}.#{extension}")
    end

    # Le dernier log, ou nil
    def log
      path = state_file('log')
      return unless File.exist?(path)
      # Explicite : sous systemd, sans LANG, Ruby lirait le fichier en US-ASCII
      File.read(path, encoding: 'UTF-8').scrub
    end

    def start_log(text)
      write_state('log', text)
    end

    def append_log(text)
      path = state_file('log')
      File.write(path, text, mode: 'a') if File.exist?(path)
    end

    # queued, building, success, failure, ou unknown
    def status
      path = state_file('status')
      File.exist?(path) ? File.read(path).strip : 'unknown'
    end

    def status=(value)
      write_state('status', value)
    end

    # Espace disque, additionné sur l'accueil
    def size=(bytes)
      write_state('size', bytes)
    end

    # Un seul build à la fois par site, y compris entre processus Puma
    def lock
      FileUtils.mkdir_p(File.dirname(state_file('lock')))
      File.open(state_file('lock'), File::CREAT) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    # Une publication est en cours : le verrou est pris
    def running?
      path = state_file('lock')
      return false unless File.exist?(path)
      File.open(path) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }
    end

    private

    def write_state(extension, content)
      FileUtils.mkdir_p(File.dirname(state_file(extension)))
      File.write(state_file(extension), content)
    end
  end
end
