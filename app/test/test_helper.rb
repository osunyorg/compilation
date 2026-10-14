ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'tmpdir'
require_relative '../app'

# Les chemins de production (/srv/kelmscott, app/config) sont remplacés par un dossier temporaire
module TestPaths
  ROOT = Dir.mktmpdir('kelmscott-test')

  def self.replace(owner, name, path)
    owner.send(:remove_const, name)
    owner.const_set(name, path)
  end

  replace Publication, :SITES_PATH, File.join(ROOT, 'sites')
  replace Publication, :STATE_PATH, File.join(ROOT, 'state')
  replace Helpers, :PRIVATE_KEY_PATH, File.join(ROOT, 'kelmscott.key')
  replace Helpers, :TOKEN_PATH, File.join(ROOT, 'kelmscott.token')

  Minitest.after_run { FileUtils.rm_rf(ROOT) }
end

class KelmscottTest < Minitest::Test
  TOKEN = 'jeton-de-test'

  def setup
    FileUtils.rm_rf(Dir[File.join(TestPaths::ROOT, '*')])
    FileUtils.mkdir_p([Publication::SITES_PATH, Publication::STATE_PATH])
  end

  # Crée la paire de clés et le jeton, comme bin/setup-keys, et renvoie la clé publique
  def configure_keys
    private_key = RbNaCl::PrivateKey.generate
    File.write(Helpers::PRIVATE_KEY_PATH, Base64.strict_encode64(private_key.to_bytes))
    File.write(Helpers::TOKEN_PATH, TOKEN)
    private_key.public_key
  end

  # Chiffre un secret comme le fait l'admin Osuny
  def encrypt(public_key, value)
    Base64.strict_encode64(RbNaCl::Boxes::Sealed.from_public_key(public_key).encrypt(value))
  end

  def write_state(university, site, extension, content)
    FileUtils.mkdir_p(File.join(Publication::STATE_PATH, university))
    File.write(File.join(Publication::STATE_PATH, university, "#{site}.#{extension}"), content)
  end

  def read_state(university, site, extension)
    File.read(File.join(Publication::STATE_PATH, university, "#{site}.#{extension}"), encoding: 'UTF-8')
  end
end
