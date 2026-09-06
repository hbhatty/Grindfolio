class NotionApplicationStatusChange < ApplicationRecord
  belongs_to :notion_application

  validates :detected_on, :detected_at, presence: true
  validates :from_status, :to_status, length: { minimum: 1 }, allow_nil: true
  validate :status_actually_changed

  private
    def status_actually_changed
      return if from_status != to_status

      errors.add(:to_status, "must differ from the previous status")
    end
end
