class LeetcodeDailyActivity < ApplicationRecord
  belongs_to :leetcode_connection, inverse_of: :daily_activities

  validates :activity_date,
    presence: true,
    uniqueness: { scope: :leetcode_connection_id }
  validates :submission_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :activity_is_not_before_tracking_started

  private
    def activity_is_not_before_tracking_started
      return if activity_date.blank? || leetcode_connection.blank?
      return if activity_date >= leetcode_connection.tracking_started_on

      errors.add(:activity_date, "cannot be before LeetCode tracking started")
    end
end
