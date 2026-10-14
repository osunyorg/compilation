require 'fileutils'
require 'json'

class Publication
  # File d'attente des publications, sur le disque : elle survit à un redémarrage.
  # Une seule demande en attente par site, la dernière reçue : cent demandes pour un site donnent une publication.
  # Les demandes sont écrites telles que reçues : les secrets restent chiffrés jusqu'à la synchronisation.
  class Queue
    # Publications simultanées par processus Puma
    WORKERS = 2
    # Délai entre deux consultations de la file, quand elle est vide
    POLL_INTERVAL = 2

    def self.path
      File.join(Site::STATE_PATH, '.queue')
    end

    def self.push(university, site, request)
      directory = File.join(path, university)
      FileUtils.mkdir_p(directory)
      # Écrit à côté puis renommé : un processus qui dépile ne lit jamais une demande à moitié écrite
      temporary = File.join(directory, ".#{site}.#{Process.pid}.#{Thread.current.object_id}")
      File.write(temporary, JSON.generate(request))
      File.rename(temporary, File.join(directory, "#{site}.json"))
      # Pendant une publication du même site, le statut reste « en cours »
      state = Site.new(university, site)
      state.status = 'queued' unless state.status == 'building'
    end

    # La demande la plus ancienne d'un site qui n'est pas en cours de publication.
    # Le renommage est atomique : entre plusieurs processus, un seul obtient la demande.
    def self.pop
      # Une demande prise entre-temps par un autre processus passe en dernier, puis est ignorée
      Dir.glob(File.join(path, '*', '*.json')).sort_by { |file| File.mtime(file) rescue Time.now }.each do |file|
        university = File.basename(File.dirname(file))
        site = File.basename(file, '.json')
        next if Site.new(university, site).running?
        claimed = "#{file}.#{Process.pid}.#{Thread.current.object_id}"
        File.rename(file, claimed)
        request = JSON.parse(File.read(claimed))
        File.delete(claimed)
        return [university, site, request]
      rescue Errno::ENOENT
        # Prise par un autre processus entre-temps
        next
      end
      nil
    end

    # Lance les publications de la file, une à la fois par thread. Appelé au démarrage de chaque processus Puma.
    def self.start
      WORKERS.times do
        Thread.new do
          loop { work || sleep(POLL_INTERVAL) }
        end
      end
    end

    # Publie la demande suivante, et dit s'il y en avait une
    def self.work
      university, site, request = pop
      return false if university.nil?
      Publication.new(university, site, request['git_url'], request['sync_method'], request['variables']).run
      true
    rescue StandardError => e
      warn "[#{university}/#{site}] #{e.class}: #{e.message}"
      true
    end
  end
end
