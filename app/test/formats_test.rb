require_relative 'test_helper'

class FormatsTest < Minitest::Test
  MEGABYTE = 1024**2
  GIGABYTE = 1024**3

  def test_size_in_megabytes
    assert_equal '0 Mo', Formats.format_size(0)
    assert_equal '1 Mo', Formats.format_size(900 * 1024)
    assert_equal '962 Mo', Formats.format_size((961.9 * MEGABYTE).to_i)
  end

  def test_size_in_gigabytes
    assert_equal '1,0 Go', Formats.format_size((1023.6 * MEGABYTE).to_i)
    assert_equal '5,0 Go', Formats.format_size(5 * GIGABYTE)
    assert_equal '12,4 Go', Formats.format_size((12.44 * GIGABYTE).to_i)
  end

  def test_duration
    assert_equal '0 s', Formats.format_duration(0.4)
    assert_equal '4 s', Formats.format_duration(4)
    assert_equal '1 min 0 s', Formats.format_duration(59.6)
    assert_equal '1 min 23 s', Formats.format_duration(83)
  end

  def test_time
    assert_equal '14/10/2026 01:48:39 UTC', Formats.format_time(Time.utc(2026, 10, 14, 1, 48, 39))
  end

  def test_private_in_publication
    publication = Publication.new('universite', 'site', 'https://example.org/site.git', 'dxfl', {})
    assert_raises(NoMethodError) { publication.format_size(0) }
  end
end
