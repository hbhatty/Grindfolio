require "digest"

class EmailVerificationResendsController < ApplicationController
  RESEND_RATE_LIMIT = 10
  RESEND_RATE_LIMIT_WINDOW = 3.minutes
  EMAIL_COOLDOWN = 1.minute

  protect_from_forgery with: :exception
  rate_limit to: RESEND_RATE_LIMIT,
    within: RESEND_RATE_LIMIT_WINDOW,
    only: :create,
    with: -> { render :rate_limited, status: :too_many_requests }

  after_action :enqueue_verification_email, only: :create

  def new
  end

  def accepted
  end

  def create
    normalized_email_address = PasswordCredential.normalize_value_for(
      :email_address,
      resend_params[:email_address].to_s
    )

    if claim_email_cooldown(normalized_email_address)
      @password_credential_for_delivery = PasswordCredential.find_by(
        email_address: normalized_email_address,
        email_verified_at: nil
      )
    end

    redirect_to email_verification_resend_accepted_path, status: :see_other
  end

  private
    def resend_params
      params.require(:email_verification_resend).permit(:email_address)
    end

    def claim_email_cooldown(email_address)
      Rails.cache.write(
        cooldown_cache_key(email_address),
        true,
        expires_in: EMAIL_COOLDOWN,
        unless_exist: true
      )
    end

    def cooldown_cache_key(email_address)
      digest = Digest::SHA256.hexdigest(email_address)
      "email-verification-resend:#{digest}"
    end

    def enqueue_verification_email
      return unless @password_credential_for_delivery

      EmailVerificationMailer.verify(@password_credential_for_delivery).deliver_later
    end
end
