class LeetcodeConnection < ApplicationRecord
  belongs_to :user
  has_many :daily_activities,
    class_name: "LeetcodeDailyActivity",
    dependent: :destroy,
    inverse_of: :leetcode_connection

  normalizes :username, with: ->(username) { username.strip }

  validates :username,
    presence: true,
    length: { maximum: 64 },
    uniqueness: { case_sensitive: false }
  validates :user_id, uniqueness: true
  validates :tracking_started_on, :verified_at, presence: true
end
