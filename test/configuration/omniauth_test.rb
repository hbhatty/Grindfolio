require "test_helper"

class OmniAuthConfigurationTest < ActiveSupport::TestCase
  test "uses GitHub App user authorization without OAuth App scopes" do
    assert_equal :github_app, Rails.application.config.x.github.authorization_app
    assert_nil Rails.application.config.x.github.oauth_scope
  end

  test "requires a CSRF-protected POST to begin authorization" do
    assert_equal [ :post ], OmniAuth.config.allowed_request_methods
    assert_instance_of OmniAuth::RailsCsrfProtection::TokenVerifier,
      OmniAuth.config.request_validation_phase
  end
end
