class GithubConnection < ApplicationRecord
  belongs_to :external_identity
  has_many :daily_contributions,
    class_name: "GithubDailyContribution",
    dependent: :destroy,
    inverse_of: :github_connection

  enum :sync_status,
    {
      pending: "pending",
      syncing: "syncing",
      ready: "ready",
      error: "error"
    },
    prefix: true,
    validate: true

  validates :external_identity_id, uniqueness: true
  validates :tracking_started_on, presence: true
  validate :identity_is_github

  delegate :user, to: :external_identity

  private
    def identity_is_github
      return if external_identity&.provider == "github"

      errors.add(:external_identity, "must be a GitHub identity")
    end
end
