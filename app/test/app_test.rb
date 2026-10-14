require_relative 'test_helper'

class AppTest < KelmscottTest
  include Rack::Test::Methods

  # Publications demandées par les requêtes, sans les exécuter
  PUBLICATIONS = Queue.new

  def app
    Sinatra::Application
  end

  def setup
    super
    @public_key = configure_keys
    PUBLICATIONS.clear
  end

  def publish(body, token: TOKEN, content_type: 'application/json')
    header 'Authorization', "Bearer #{token}"
    header 'Content-Type', content_type
    post '/universite/site', body.is_a?(String) ? body : body.to_json
  end

  def valid_body
    {
      git_url: 'https://github.com/osunyorg/site.git',
      sync_method: 's3',
      variables: {
        S3_BUCKET: 'bucket',
        AWS_ACCESS_KEY_ID: 'id',
        AWS_SECRET_ACCESS_KEY: encrypt(@public_key, 'secret')
      }
    }
  end

  # Remplace Publication.new le temps d'un bloc, et renvoie les arguments de la publication lancée
  def recording_publication
    Publication.define_singleton_method(:new) do |*arguments|
      PUBLICATIONS << arguments
      Struct.new(:run).new
    end
    yield
    # La publication est lancée dans un thread
    PUBLICATIONS.pop(timeout: 1)
  ensure
    Publication.singleton_class.remove_method(:new)
  end

  # Pages

  def test_home
    write_state('universite', 'site', 'size', 5 * 1024**3)
    FileUtils.mkdir_p(File.join(Publication::SITES_PATH, 'universite', 'site'))
    get '/'
    assert last_response.ok?
    free_space, total_space = Object.new.extend(Helpers).disk_space
    assert_includes last_response.body, 'universite'
    assert_match(%r{<th>Espace utilisé par Kelmscott</th>\s*<td>5,0 Go</td>}, last_response.body)
    assert_match(%r{<th>Espace libre</th>\s*<td>#{Regexp.escape("#{Formats.format_size(free_space)} sur #{Formats.format_size(total_space)}")}</td>}, last_response.body)
  end

  def test_university
    FileUtils.mkdir_p(File.join(Publication::SITES_PATH, 'universite', 'site'))
    get '/universite'
    assert last_response.ok?
    assert_includes last_response.body, 'site'
  end

  def test_site_logs_in_utf8_without_lang
    write_state('universite', 'site', 'log', 'Durée : 4 s')
    # Comme sous systemd sans LANG ; $VERBOSE masque l'avertissement de Ruby, voulu ici
    default_external, verbose = Encoding.default_external, $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = Encoding::US_ASCII
    get '/universite/site'
    assert last_response.ok?
    assert_includes last_response.body, 'Durée : 4 s'
  ensure
    Encoding.default_external = default_external
    $VERBOSE = verbose
  end

  # Badge

  def test_badge_states
    { nil => 'inconnu', 'building' => 'en cours', 'success' => 'succès', 'failure' => 'échec' }.each do |status, text|
      write_state('universite', 'site', 'status', status) if status
      get '/universite/site/badge.svg'
      assert last_response.ok?
      assert_equal 'image/svg+xml', last_response.media_type
      assert_equal 'no-cache', last_response.headers['Cache-Control']
      assert_includes last_response.body, "<title>Kelmscott : #{text}</title>"
    end
  end

  def test_badge_invalid_name
    get '/universite/..site/badge.svg'
    assert_equal 400, last_response.status
  end

  # Demandes de publication

  def test_publish
    arguments = recording_publication { publish(valid_body) }
    assert_equal 202, last_response.status
    university, site, git_url, sync_method, environment = arguments
    assert_equal %w[universite site https://github.com/osunyorg/site.git s3], [university, site, git_url, sync_method]
    assert_equal({ 'S3_BUCKET' => 'bucket', 'AWS_ACCESS_KEY_ID' => 'id', 'AWS_SECRET_ACCESS_KEY' => 'secret' }, environment)
  end

  def test_publish_without_keys
    FileUtils.rm_f(Helpers::PRIVATE_KEY_PATH)
    publish(valid_body)
    assert_equal 503, last_response.status
  end

  def test_publish_without_token
    publish(valid_body, token: 'mauvais')
    assert_equal 401, last_response.status
  end

  def test_publish_requires_json
    publish('git_url=x', content_type: 'application/x-www-form-urlencoded')
    assert_equal 415, last_response.status
  end

  def test_publish_invalid_json
    publish('{')
    assert_equal 400, last_response.status
  end

  def test_publish_invalid_git_url
    publish(valid_body.merge(git_url: 'file:///etc'))
    assert_equal 'Invalid git_url', last_response.body
  end

  def test_publish_invalid_sync_method
    publish(valid_body.merge(sync_method: 'ftp'))
    assert_equal 'Invalid sync_method', last_response.body
  end

  def test_publish_unknown_variable
    publish(valid_body.merge(variables: { PATH: '/tmp' }))
    assert_equal 'Unknown variables: PATH', last_response.body
  end

  def test_publish_undecryptable_secret
    publish(valid_body.merge(variables: { AWS_SECRET_ACCESS_KEY: 'pas chiffré' }))
    assert_equal 'Secret decryption failed', last_response.body
  end

  def test_publish_invalid_site
    header 'Authorization', "Bearer #{TOKEN}"
    header 'Content-Type', 'application/json'
    post '/universite/..site', valid_body.to_json
    assert_equal 'Invalid site', last_response.body
  end
end
