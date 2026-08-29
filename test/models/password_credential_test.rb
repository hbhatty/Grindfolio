require "test_helper"

class PasswordCredentialTest < ActiveSupport::TestCase
  PASSWORD = "correct horse battery staple"

  test "normalizes the email and authenticates the password" do
    credential = PasswordCredential.create!(
      user: User.create!,
      email_address: "  Developer@Example.COM ",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )

    assert_equal "developer@example.com", credential.email_address
    assert_equal credential, credential.authenticate(PASSWORD)
    assert_not credential.authenticate("incorrect password")
  end

  test "requires at least eight password characters" do
    credential = PasswordCredential.new(
      user: User.create!,
      email_address: "developer@example.com",
      password: "short",
      password_confirmation: "short"
    )

    assert_not credential.valid?
    assert_includes credential.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "rejects a password over the bcrypt byte limit" do
    password = "é" * 37
    credential = PasswordCredential.new(
      user: User.create!,
      email_address: "developer@example.com",
      password:,
      password_confirmation: password
    )

    assert_operator password.length, :<, PasswordCredential::PASSWORD_MAXIMUM_BYTES
    assert_operator password.bytesize, :>, PasswordCredential::PASSWORD_MAXIMUM_BYTES
    assert_not credential.valid?
    assert_includes credential.errors.details[:password], { error: :password_too_long }
  end

  test "accepts a password at exactly the bcrypt byte limit" do
    password = "a" * PasswordCredential::PASSWORD_MAXIMUM_BYTES
    credential = PasswordCredential.new(
      user: User.create!,
      email_address: "developer@example.com",
      password:,
      password_confirmation: password
    )

    assert credential.valid?
  end

  test "allows only one password credential per user" do
    user = User.create!
    create_credential(user:, email_address: "first@example.com")

    duplicate = PasswordCredential.new(
      user:,
      email_address: "second@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "requires a unique normalized email" do
    create_credential(user: User.create!, email_address: "developer@example.com")

    duplicate = PasswordCredential.new(
      user: User.create!,
      email_address: "DEVELOPER@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end

  test "generates a token for the current email verification state" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:email_verification)

    assert_equal credential, PasswordCredential.find_by_token_for(:email_verification, token)

    credential.update!(email_address: "new-address@example.com")

    assert_nil PasswordCredential.find_by_token_for(:email_verification, token)
  end

  test "invalidates the token after the email is verified" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:email_verification)

    credential.update!(email_verified_at: Time.current)

    assert_nil PasswordCredential.find_by_token_for(:email_verification, token)
  end

  test "expires the email verification token after twenty-four hours" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:email_verification)

    travel_to(PasswordCredential::EMAIL_VERIFICATION_TOKEN_LIFETIME.from_now + 1.second) do
      assert_nil PasswordCredential.find_by_token_for(:email_verification, token)
    end
  end

  test "generates a password reset token for the current email and password digest" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:password_reset)

    assert_equal credential, PasswordCredential.find_by_token_for(:password_reset, token)

    credential.update!(email_address: "new-address@example.com")

    assert_nil PasswordCredential.find_by_token_for(:password_reset, token)
  end

  test "invalidates the password reset token after the password changes" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:password_reset)
    replacement_password = "new correct horse battery staple"

    credential.update!(
      password: replacement_password,
      password_confirmation: replacement_password
    )

    assert_nil PasswordCredential.find_by_token_for(:password_reset, token)
  end

  test "expires the password reset token after one hour" do
    credential = create_credential(user: User.create!, email_address: "developer@example.com")
    token = credential.generate_token_for(:password_reset)

    travel_to(PasswordCredential::PASSWORD_RESET_TOKEN_LIFETIME.from_now + 1.second) do
      assert_nil PasswordCredential.find_by_token_for(:password_reset, token)
    end
  end

  private
    def create_credential(user:, email_address:)
      PasswordCredential.create!(
        user:,
        email_address:,
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
    end
end
