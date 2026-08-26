class User < ApplicationRecord
  IANA_TIME_ZONE_IDENTIFIERS = TZInfo::Timezone.all_identifiers.freeze

  has_one :password_credential, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :external_identities, dependent: :destroy
  has_one :leetcode_connection, dependent: :destroy
  has_one :notion_connection, dependent: :destroy
  has_many :leetcode_daily_activities, through: :leetcode_connection, source: :daily_activities
  has_many :leetcode_verification_challenges, dependent: :destroy

  validate :time_zone_is_valid_iana_identifier

  private
    def time_zone_is_valid_iana_identifier
      return if time_zone.nil?

      TZInfo::Timezone.get(time_zone)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:time_zone, "is not a valid IANA time zone")
    end
end
