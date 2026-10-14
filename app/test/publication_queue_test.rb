require_relative 'test_helper'

class PublicationQueueTest < KelmscottTest
  def request(git_url)
    { 'git_url' => git_url, 'sync_method' => 's3', 'variables' => {} }
  end

  def test_pop_empty
    assert_nil PublicationQueue.pop
  end

  # Une seule demande en attente par site : la dernière reçue
  def test_keeps_last_request_per_site
    PublicationQueue.push('universite', 'site', request('https://github.com/osunyorg/premier.git'))
    PublicationQueue.push('universite', 'site', request('https://github.com/osunyorg/dernier.git'))
    _, _, popped = PublicationQueue.pop
    assert_equal 'https://github.com/osunyorg/dernier.git', popped['git_url']
    assert_nil PublicationQueue.pop
  end

  # Les plus anciennes d'abord
  def test_order
    PublicationQueue.push('universite', 'premier', request('https://github.com/osunyorg/premier.git'))
    FileUtils.touch(File.join(PublicationQueue.path, 'universite', 'premier.json'), mtime: Time.now - 10)
    PublicationQueue.push('universite', 'second', request('https://github.com/osunyorg/second.git'))
    assert_equal 'premier', PublicationQueue.pop[1]
    assert_equal 'second', PublicationQueue.pop[1]
  end

  # Un site en cours de publication reste en attente, sans bloquer les autres
  def test_skips_running_site
    PublicationQueue.push('universite', 'occupe', request('https://github.com/osunyorg/occupe.git'))
    PublicationQueue.push('universite', 'libre', request('https://github.com/osunyorg/libre.git'))
    lock_path = Publication.state_file('universite', 'occupe', 'lock')
    File.open(lock_path, File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      assert_equal 'libre', PublicationQueue.pop[1]
      assert_nil PublicationQueue.pop
    end
    assert_equal 'occupe', PublicationQueue.pop[1]
  end

  # Pendant une publication, le statut reste « en cours »
  def test_keeps_building_status
    write_state('universite', 'site', 'status', 'building')
    PublicationQueue.push('universite', 'site', request('https://github.com/osunyorg/site.git'))
    assert_equal 'building', read_state('universite', 'site', 'status')
  end

  def test_work
    PublicationQueue.push('universite', 'site', request('https://github.com/osunyorg/site.git'))
    published = []
    Publication.define_singleton_method(:new) { |*arguments| published << arguments; Struct.new(:run).new }
    assert PublicationQueue.work
    refute PublicationQueue.work
    assert_equal [['universite', 'site', 'https://github.com/osunyorg/site.git', 's3', {}]], published
  ensure
    Publication.singleton_class.remove_method(:new)
  end
end
