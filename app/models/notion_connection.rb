class NotionConnection < ApplicationRecord
  encrypts :access_token
  encrypts :refresh_token

  belongs_to :user

  validates :user_id, :bot_id, uniqueness: true
  validates :workspace_id,
    :bot_id,
    :access_token,
    :refresh_token,
    :tracking_started_on,
    :authorized_at,
    presence: true
end
