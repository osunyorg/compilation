require 'base64'
require 'rbnacl'

class Publication
  # Variables de synchronisation d'un site, envoyées par l'admin Osuny
  module Variables
    # Liste blanche, identique à Communication::Website::Variable dans l'admin Osuny
    # Chaque méthode correspond à un script dans sync/, installé par bin/steps/sandbox
    KEYS_BY_SYNC_METHOD = {
      'sftp' => %w[SFTP_HOST SFTP_PORT SFTP_USER SFTP_PASSWORD SFTP_PATH],
      'dxfl' => %w[DXFL_BUCKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY],
      'rsync' => %w[RSYNC_HOST RSYNC_PORT RSYNC_USER RSYNC_PATH RSYNC_SSH_PRIVATE_KEY RSYNC_BASTION_HOST RSYNC_BASTION_PORT RSYNC_BASTION_USER],
      's3' => %w[S3_BUCKET S3_ENDPOINT S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY]
    }.freeze
    SECRET_KEYS = %w[SFTP_PASSWORD RSYNC_SSH_PRIVATE_KEY AWS_SECRET_ACCESS_KEY].freeze

    # Générée par bin/configure/keys, jamais versionnée
    PRIVATE_KEY_PATH = File.expand_path('../../config/kelmscott.key', __dir__)

    # Les secrets déchiffrés, par nom. Ils sont chiffrés par l'admin avec la clé publique de Kelmscott (sealed box libsodium).
    def self.secrets(variables)
      variables.slice(*SECRET_KEYS).transform_values { |value| decrypt(value) }
    end

    def self.decrypt(value)
      private_key = RbNaCl::PrivateKey.new(Base64.strict_decode64(File.read(PRIVATE_KEY_PATH).strip))
      RbNaCl::Boxes::Sealed.from_private_key(private_key).decrypt(Base64.strict_decode64(value))
    end
  end
end
