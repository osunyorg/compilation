require_relative 'test_helper'

class SiteTest < KelmscottTest
  def site
    @site ||= Publication::Site.new('universite', 'site')
  end

  def test_unknown_status
    assert_equal 'unknown', site.status
  end

  def test_status
    site.status = 'success'
    assert_equal 'success', site.status
  end

  def test_append_log_only_after_start
    site.append_log('perdu')
    assert_nil site.log
    site.start_log("Début\n")
    site.append_log('suite')
    assert_equal "Début\nsuite", site.log
  end

  def test_running
    refute site.running?
    site.lock { assert site.running? }
    refute site.running?
  end
end
