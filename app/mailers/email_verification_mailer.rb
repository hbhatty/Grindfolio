class EmailVerificationMailer < ApplicationMailer
  def verify(password_credential)
    @password_credential = password_credential
    @verification_token = @password_credential.generate_token_for(:email_verification)

    mail(
      to: @password_credential.email_address,
      subject: "Verify your Gridfolio email"
    )
  end
end
