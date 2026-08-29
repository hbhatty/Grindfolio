require "digest"

class PasswordResetRequestsController < ApplicationController
  REQUEST_RATE_LIMIT = 10
  REQUEST_RATE_LIMIT_WINDOW = 3.minutes
  EMAIL_COOLDOWN = 1.minute

  protect_from_forgery with: :exception
  rate_limit to: REQUEST_RATE_LIMIT,
    within: REQUEST_RATE_LIMIT_WINDOW,
    only: :create,
    with: -> { render :rate_limited, status: :too_many_requests }

  after_action :enqueue_password_reset_email, only: :create

  def new
  end

  def accepted
  end

  def create
    normalized_email_address = PasswordCredential.normalize_value_for(
      :email_address,
      reset_request_params[:email_address].to_s
    )

    if claim_email_cooldown(normalized_email_address)
      @password_credential_for_delivery = PasswordCredential
        .where.not(email_verified_at: nil)
        .find_by(email_address: normalized_email_address)
    end

    redirect_to password_reset_request_accepted_path, status: :see_other
  end

  private
    def reset_request_params
      params.require(:password_reset_request).permit(:email_address)
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
      "password-reset-request:#{digest}"
    end

    def enqueue_password_reset_email
      return unless @password_credential_for_delivery

      PasswordResetMailer.reset(@password_credential_for_delivery).deliver_later
    end
end
