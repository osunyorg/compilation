workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))
threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', 5))
threads threads_count, threads_count

preload_app!

# Chaque processus dépile la file d'attente des publications : il faut au moins un worker (WEB_CONCURRENCY)
before_worker_boot { PublicationQueue.start }

# Seulement en local : nginx est le seul point d'entrée (HTTPS), même si le pare-feu était désactivé
bind "tcp://127.0.0.1:#{ENV.fetch('PORT', 3000)}"
environment ENV.fetch('RACK_ENV', 'production')
