class ExternalIdentity < ApplicationRecord
  PROVIDERS = %w[github google].freeze

  belongs_to :user
  has_one :github_connection, dependent: :destroy

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :user_id }
  validates :provider_uid, presence: true, uniqueness: { scope: :provider }

  scope :github, -> { where(provider: "github") }
end
