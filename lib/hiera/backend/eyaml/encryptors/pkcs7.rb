require 'openssl'
require 'hiera/backend/eyaml/encryptor'
require 'hiera/backend/eyaml/encrypthelper'
require 'hiera/backend/eyaml/logginghelper'
require 'hiera/backend/eyaml/options'

class Hiera
  module Backend
    module Eyaml
      module Encryptors
        class Pkcs7 < Encryptor
          self.options = {
            private_key: { desc: 'Path to private key',
                           type: :string,
                           default: './keys/private_key.pkcs7.pem', },
            public_key: { desc: 'Path to public key',
                          type: :string,
                          default: './keys/public_key.pkcs7.pem', },
            private_key_env_var: { desc: 'Name of environment variable to read private key from',
                                   type: :string, },
            public_key_env_var: { desc: 'Name of environment variable to read public key from',
                                  type: :string, },
            keysize: { desc: 'Key size used for encryption',
                       type: :integer,
                       default: 2048, },
          }

          self.tag = 'PKCS7'


          def self.encrypt(plaintext)
            LoggingHelper.trace 'PKCS7 encrypt'

            public_key_pem = self.load_public_key_pem()
            public_key_x509 = OpenSSL::X509::Certificate.new(public_key_pem)

            cipher = OpenSSL::Cipher.new('aes-256-cbc')
            OpenSSL::PKCS7.encrypt([public_key_x509], plaintext, cipher, OpenSSL::PKCS7::BINARY).to_der
          end

          def self.decrypt(ciphertext)
            LoggingHelper.trace 'PKCS7 decrypt'

            private_key_pem = self.load_private_key_pem()
            private_key_rsa = OpenSSL::PKey::RSA.new(private_key_pem)

            public_key_pem = self.load_public_key_pem()
            public_key_x509 = OpenSSL::X509::Certificate.new(public_key_pem)

            pkcs7 = OpenSSL::PKCS7.new(ciphertext)
            pkcs7.decrypt(private_key_rsa, public_key_x509)
          end

          def self.create_keys
            # Try to do equivalent of:
            # openssl req -x509 -nodes -days 100000 -newkey rsa:2048 -keyout privatekey.pem -out publickey.pem -subj '/'

            public_key = option :public_key
            private_key = option :private_key
            keysize = option :keysize

            key = OpenSSL::PKey::RSA.new(keysize)
            EncryptHelper.ensure_key_dir_exists private_key
            EncryptHelper.write_important_file filename: private_key, content: key.to_pem, mode: 0o600

            cert = OpenSSL::X509::Certificate.new
            cert.serial = 1
            cert.public_key = key.public_key
            cert.sign(key, OpenSSL::Digest::SHA256.new)

            EncryptHelper.ensure_key_dir_exists public_key
            EncryptHelper.write_important_file filename: public_key, content: cert.to_pem
            LoggingHelper.info 'Keys created OK'
          end

          protected

          def self.load_ANY_key_pem(optname_key, optname_env_var)
            opt_key = option (optname_key.to_sym)
            opt_key_env_var = option (optname_env_var.to_sym)

            if opt_key and opt_key_env_var
              warn "both #{optname_key} and #{optname_env_var} specified, using #{optname_env_var}"
            end

            if opt_key_env_var
              raise StandardError, "env #{opt_key_env_var} is not set" unless ENV[opt_key_env_var]
              opt_key_pem = ENV[opt_key_env_var]
            elsif opt_key
              raise StandardError, "file #{opt_key} does not exist" unless File.exist? opt_key
              opt_key_pem = File.read opt_key
            else
              raise StandardError, "pkcs7_#{optname_key} is not defined" unless opt_key or opt_key_env_var
            end

            return opt_key_pem
          end

          def self.load_public_key_pem
            return self.load_ANY_key_pem('public_key', 'public_key_env_var')
          end

          def self.load_private_key_pem
            return self.load_ANY_key_pem('private_key', 'private_key_env_var')
          end

        end
      end
    end
  end
end
