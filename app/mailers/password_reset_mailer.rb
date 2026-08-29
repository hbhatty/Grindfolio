class PasswordResetMailer < ApplicationMailer
  def reset(password_credential)
    @password_credential = password_credential
    @reset_token = @password_credential.generate_token_for(:password_reset)

    mail(
      to: @password_credential.email_address,
      subject: "Reset your Grindfolio password"
    )
  end
end
