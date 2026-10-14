require_relative '../formats'

class Publication
  # Début et récapitulatif du log d'une publication : durées des étapes et poids du site, même en cas d'échec
  class Report
    include Formats

    def initialize(site)
      @site = site
      @durations = {}
    end

    def start
      @started_at = Time.now
      site.start_log("Début : #{format_time(started_at)}\n\n")
    end

    # Mesure la durée d'une étape, y compris en cas d'échec
    def step(name)
      step_started_at = Time.now
      yield
    ensure
      durations[name] = Time.now - step_started_at
    end

    def finish
      size = disk_usage(site.path)
      site.size = size
      site.append_log(summary(size))
    end

    private

    attr_reader :site, :durations, :started_at

    def summary(size)
      finished_at = Time.now
      lines = ['', "Fin : #{format_time(finished_at)}"]
      lines << "Durée : #{format_duration(finished_at - started_at)}"
      lines += durations.map { |name, duration| "  #{name} : #{format_duration(duration)}" }
      lines << "Poids : #{format_size(size)}"
      lines += size_details(size).map { |name, bytes| "  #{name} : #{format_size(bytes)}" }
      lines.join("\n") + "\n"
    end

    # Détail du poids : les morceaux mesurés, et par différence les sources du dépôt et les caches du build
    # (node_modules n'est qu'un lien vers la toolchain partagée)
    def size_details(size)
      repository = disk_usage(site.repository_path)
      details = {
        'Site compilé (public)' => disk_usage(site.public_path),
        'Historique git (.git)' => disk_usage(File.join(site.repository_path, '.git'))
      }
      details['Sources'] = repository - details.values.sum
      details['Caches'] = size - repository
      details
    end

    # Espace disque réel d'un dossier, en octets (0 s'il n'existe pas)
    def disk_usage(path)
      IO.popen(['du', '-sk', path], err: File::NULL, &:read).to_i * 1024
    end
  end
end
