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
  replace Helpers, :ADMIN_KEY_PATH, File.join(ROOT, 'admin.pub')

  Minitest.after_run { FileUtils.rm_rf(ROOT) }
end

class KelmscottTest < Minitest::Test

  def setup
    FileUtils.rm_rf(Dir[File.join(TestPaths::ROOT, '*')])
    FileUtils.mkdir_p([Publication::SITES_PATH, Publication::STATE_PATH])
  end

  # Crée la paire de clés de Kelmscott et enregistre la clé publique de signature de l'admin,
  # comme bin/configure/keys, et renvoie la clé publique de Kelmscott et la clé de signature de l'admin
  def configure_keys
    private_key = RbNaCl::PrivateKey.generate
    signing_key = RbNaCl::SigningKey.generate
    File.write(Helpers::PRIVATE_KEY_PATH, Base64.strict_encode64(private_key.to_bytes))
    File.write(Helpers::ADMIN_KEY_PATH, Base64.strict_encode64(signing_key.verify_key.to_bytes))
    [private_key.public_key, signing_key]
  end

  # Signe une demande comme le fait l'admin Osuny
  def sign(signing_key, timestamp, path, body)
    Base64.strict_encode64(signing_key.sign("#{timestamp}\nPOST #{path}\n#{body}"))
  end

  # Chiffre un secret comme le fait l'admin Osuny
  def encrypt(public_key, value)
    Base64.strict_encode64(RbNaCl::Boxes::Sealed.from_public_key(public_key).encrypt(value))
  end

  def write_state(university, site, extension, content)
    path = Publication.state_file(university, site, extension)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read_state(university, site, extension)
    File.read(Publication.state_file(university, site, extension), encoding: 'UTF-8')
  end
end
