require "test_helper"

class EmailVerificationMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery staple"

  test "renders a tokenized verification link in HTML and text" do
    credential = create_credential
    email = EmailVerificationMailer.verify(credential)

    assert_equal [ credential.email_address ], email.to
    assert_equal "Verify your Gridfolio email", email.subject
    assert_match(%r{/email_verification/[^\s\"<]+}, email.html_part.body.to_s)
    assert_match(%r{/email_verification/[^\s]+}, email.text_part.body.to_s)
    assert_includes email.html_part.body.to_s, "This link expires in 24 hours."
    assert_includes email.text_part.body.to_s, "This link expires in 24 hours."
  end

  test "can be queued for later delivery" do
    credential = create_credential

    assert_enqueued_emails 1 do
      EmailVerificationMailer.verify(credential).deliver_later
    end
  end

  private
    def create_credential
      PasswordCredential.create!(
        user: User.create!,
        email_address: "developer@example.com",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
    end
end
