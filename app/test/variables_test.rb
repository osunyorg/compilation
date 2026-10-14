require_relative 'test_helper'

class VariablesTest < KelmscottTest
  def test_secrets
    public_key, = configure_keys
    variables = { 'S3_BUCKET' => 'bucket', 'AWS_SECRET_ACCESS_KEY' => encrypt(public_key, 'secret') }
    assert_equal({ 'AWS_SECRET_ACCESS_KEY' => 'secret' }, Publication::Variables.secrets(variables))
  end

  def test_undecryptable_secret
    configure_keys
    assert_raises(RbNaCl::CryptoError) { Publication::Variables.secrets('AWS_SECRET_ACCESS_KEY' => Base64.strict_encode64('x' * 64)) }
  end
end
