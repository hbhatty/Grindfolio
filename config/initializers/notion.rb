notion_client_id = Rails.application.credentials.dig(:notion, :client_id)
notion_client_secret = Rails.application.credentials.dig(:notion, :client_secret)

if Rails.env.test?
  notion_client_id ||= "test-notion-client-id"
  notion_client_secret ||= "test-notion-client-secret"
end

if notion_client_id.blank? || notion_client_secret.blank?
  raise "Missing Notion OAuth client credentials for #{Rails.env}"
end

Rails.application.config.x.notion.client_id = notion_client_id
Rails.application.config.x.notion.client_secret = notion_client_secret
