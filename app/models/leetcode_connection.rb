class LeetcodeConnection < ApplicationRecord
  belongs_to :user

  normalizes :username, with: ->(username) { username.strip }

  validates :username,
    presence: true,
    length: { maximum: 64 },
    uniqueness: { case_sensitive: false }
  validates :user_id, uniqueness: true
  validates :tracking_started_on, :verified_at, presence: true
end
