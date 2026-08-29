class PasswordCredential < ApplicationRecord
  EMAIL_VERIFICATION_TOKEN_LIFETIME = 24.hours
  PASSWORD_RESET_TOKEN_LIFETIME = 1.hour
  PASSWORD_MINIMUM_LENGTH = 8
  PASSWORD_MAXIMUM_BYTES = 72

  belongs_to :user

  has_secure_password

  generates_token_for :email_verification, expires_in: EMAIL_VERIFICATION_TOKEN_LIFETIME do
    [ email_address, email_verified_at ]
  end

  generates_token_for :password_reset, expires_in: PASSWORD_RESET_TOKEN_LIFETIME do
    [ email_address, password_digest ]
  end

  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  validates :email_address,
    presence: true,
    length: { maximum: 254 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: PASSWORD_MINIMUM_LENGTH }, if: -> { password.present? }
  validates :user_id, uniqueness: true
end
