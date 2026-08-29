require "test_helper"

class PasswordResetMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery staple"

  test "renders a tokenized reset link and expiry guidance in HTML and text" do
    credential = create_credential
    email = PasswordResetMailer.reset(credential)

    assert_equal [ credential.email_address ], email.to
    assert_equal "Reset your Grindfolio password", email.subject
    assert_match(%r{/password_reset/[^\s\"<]+}, email.html_part.body.to_s)
    assert_match(%r{/password_reset/[^\s]+}, email.text_part.body.to_s)
    assert_includes email.html_part.body.to_s, "This link expires in one hour."
    assert_includes email.text_part.body.to_s, "This link expires in one hour."
    assert_includes email.html_part.body.to_s, "If you did not request a password reset"
    assert_includes email.text_part.body.to_s, "If you did not request a password reset"
  end

  test "can be queued for later delivery" do
    credential = create_credential

    assert_enqueued_emails 1 do
      PasswordResetMailer.reset(credential).deliver_later
    end
  end

  private
    def create_credential
      PasswordCredential.create!(
        user: User.create!,
        email_address: "developer@example.com",
        password: PASSWORD,
        password_confirmation: PASSWORD,
        email_verified_at: Time.current
      )
    end
end
