class LeetcodeVerificationsController < ApplicationController
  GLOBAL_REQUEST_COOLDOWN = 5.seconds
  GLOBAL_REQUEST_KEY = "leetcode:verification:global-request"
  PROVIDER_SUSPENSION = 1.hour
  PROVIDER_SUSPENSION_KEY = "leetcode:verification:provider-suspended"
  USER_REQUEST_COOLDOWN = 1.minute

  before_action :require_authentication
  protect_from_forgery with: :exception
  rate_limit to: 10,
    within: 15.minutes,
    only: %i[create verify],
    with: -> { render :rate_limited, status: :too_many_requests }

  def create
    if Current.user.leetcode_connection
      redirect_to account_path, notice: "Your LeetCode account is already connected.", status: :see_other
      return
    end

    LeetcodeVerificationChallenge.issue_for!(
      user: Current.user,
      requested_username: verification_params[:username]
    )
    redirect_to account_path,
      notice: "Your temporary LeetCode verification challenge is ready.",
      status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to account_path,
      alert: error.record.errors.full_messages.to_sentence,
      status: :see_other
  end

  def verify
    challenge = current_challenge
    unless challenge&.usable?
      redirect_to account_path,
        alert: "That LeetCode challenge has expired or is no longer usable. Start a new one.",
        status: :see_other
      return
    end

    unless claim_provider_request
      redirect_to account_path,
        alert: "LeetCode verification is cooling down. Wait before trying again.",
        status: :see_other
      return
    end

    connection = Leetcode::VerifyConnection.new(user: Current.user, challenge:).call
    redirect_to account_path,
      notice: "LeetCode account @#{connection.username} is connected. Practice tracking starts today in UTC.",
      status: :see_other
  rescue Leetcode::VerifyConnection::ChallengeMissing
    redirect_to account_path,
      alert: "The challenge is not visible in that LeetCode README yet. Check the exact text and try again later.",
      status: :see_other
  rescue Leetcode::VerifyConnection::AlreadyConnected
    redirect_to account_path, notice: "Your LeetCode account is already connected.", status: :see_other
  rescue Leetcode::VerifyConnection::InvalidChallenge
    redirect_to account_path,
      alert: "That LeetCode challenge has expired or is no longer usable. Start a new one.",
      status: :see_other
  rescue Leetcode::VerifyConnection::UsernameUnavailable
    redirect_to account_path,
      alert: "That LeetCode account cannot be connected.",
      status: :see_other
  rescue Leetcode::PublicProfile::UserNotFound
    redirect_to account_path,
      alert: "Grindfolio could not find that public LeetCode username.",
      status: :see_other
  rescue Leetcode::PublicProfile::AccessBlocked
    suspend_provider_requests
    redirect_to account_path,
      alert: "LeetCode blocked the verification request. Verification is paused for one hour and was not retried.",
      status: :see_other
  rescue Leetcode::PublicProfile::Unavailable
    redirect_to account_path,
      alert: "LeetCode verification is temporarily unavailable. The request was not retried.",
      status: :see_other
  end

  private
    def verification_params
      params.require(:leetcode_verification).permit(:username)
    end

    def current_challenge
      Current.user.leetcode_verification_challenges
        .where(consumed_at: nil)
        .order(created_at: :desc)
        .first
    end

    def claim_provider_request
      return false if Rails.cache.exist?(PROVIDER_SUSPENSION_KEY)

      user_key = "leetcode:verification:user:#{Current.user.id}"
      return false unless Rails.cache.write(
        user_key,
        true,
        expires_in: USER_REQUEST_COOLDOWN,
        unless_exist: true
      )

      claimed_global = Rails.cache.write(
        GLOBAL_REQUEST_KEY,
        true,
        expires_in: GLOBAL_REQUEST_COOLDOWN,
        unless_exist: true
      )
      Rails.cache.delete(user_key) unless claimed_global
      claimed_global
    end

    def suspend_provider_requests
      Rails.cache.write(
        PROVIDER_SUSPENSION_KEY,
        true,
        expires_in: PROVIDER_SUSPENSION
      )
    end
end
