class GithubConnection < ApplicationRecord
  encrypts :access_token
  encrypts :refresh_token

  belongs_to :external_identity
  has_many :daily_contributions,
    class_name: "GithubDailyContribution",
    dependent: :destroy,
    inverse_of: :github_connection

  enum :sync_status,
    {
      pending: "pending",
      queued: "queued",
      syncing: "syncing",
      ready: "ready",
      error: "error",
      reauthorization_required: "reauthorization_required"
    },
    prefix: true,
    validate: true

  validates :external_identity_id, uniqueness: true
  validates :access_token, :refresh_token, :access_token_expires_at, presence: true
  validates :tracking_started_on, presence: true
  validate :identity_is_github

  delegate :user, to: :external_identity

  private
    def identity_is_github
      return if external_identity&.provider == "github"

      errors.add(:external_identity, "must be a GitHub identity")
    end
end
