class NotionApplication < ApplicationRecord
  belongs_to :notion_connection

  validates :provider_page_id,
    presence: true,
    uniqueness: { scope: :notion_connection_id }
  validates :applied_on, :company_name, :provider_last_edited_at, presence: true
  validate :applied_on_is_inside_tracking_window

  private
    def applied_on_is_inside_tracking_window
      return if applied_on.blank? || notion_connection.blank?
      return if applied_on >= notion_connection.tracking_started_on

      errors.add(:applied_on, "cannot precede Notion tracking")
    end
end
