class GithubDailyContribution < ApplicationRecord
  LEVELS = %w[
    NONE
    FIRST_QUARTILE
    SECOND_QUARTILE
    THIRD_QUARTILE
    FOURTH_QUARTILE
  ].freeze

  belongs_to :github_connection, inverse_of: :daily_contributions

  validates :activity_date, presence: true, uniqueness: { scope: :github_connection_id }
  validates :contribution_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :contribution_level, inclusion: { in: LEVELS }
  validate :activity_is_not_before_tracking_started

  private
    def activity_is_not_before_tracking_started
      return if activity_date.blank? || github_connection.blank?
      return if activity_date >= github_connection.tracking_started_on

      errors.add(:activity_date, "cannot be before GitHub tracking started")
    end
end
