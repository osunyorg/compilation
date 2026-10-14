require_relative 'test_helper'

class SandboxTest < KelmscottTest
  def site
    @site ||= Publication::Site.new('universite', 'site')
  end

  def sandbox
    @sandbox ||= Publication::Sandbox.new(site)
  end

  # Format lu par sandbox/sync, y compris pour une clé SSH sur plusieurs lignes
  def test_encode
    environment = { 'RSYNC_HOST' => 'example.org', 'RSYNC_SSH_PRIVATE_KEY' => "-----BEGIN\nclé\n-----END\n" }
    lines = sandbox.send(:encode, environment).lines(chomp: true)
    assert_equal 2, lines.size
    decoded = lines.to_h { |line| name, value = line.split('=', 2); [name, Base64.strict_decode64(value).force_encoding('UTF-8')] }
    assert_equal environment, decoded
  end

  # Les secrets déchiffrés n'apparaissent pas dans le log, ni une ligne d'une clé SSH
  def test_mask
    key = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjE\n-----END OPENSSH PRIVATE KEY-----\n"
    text = "Connexion avec motdepasse\nclé : b3BlbnNzaC1rZXktdjE\noctets \xFF\n".b
    masked = sandbox.send(:mask, text, ['motdepasse', key])
    refute_includes masked, 'motdepasse'
    refute_includes masked, 'b3BlbnNzaC1rZXktdjE'
    assert_includes masked, 'Connexion avec [secret masqué]'.b
  end

  # Le vrai chemin : la sortie de la commande est relue et masquée avant d'être écrite au log
  def test_execute_masks_output
    site.start_log('')
    assert sandbox.send(:execute, 'sh', '-c', 'cat; echo fin', input: "le secret est motdepasse\n", secrets: ['motdepasse'])
    assert_equal "le secret est [secret masqué]\nfin\n", site.log
  end
end
