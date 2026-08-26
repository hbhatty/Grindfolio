require "test_helper"

class Notion::OauthStateTest < ActiveSupport::TestCase
  test "binds a short-lived state token to one Grindfolio session" do
    session = User.create!.sessions.create!
    token = Notion::OauthState.issue(session:)

    assert Notion::OauthState.verify!(token:, session:)
  end

  test "rejects a state token from another session" do
    user = User.create!
    session = user.sessions.create!
    other_session = user.sessions.create!
    token = Notion::OauthState.issue(session:)

    assert_raises Notion::OauthState::Error do
      Notion::OauthState.verify!(token:, session: other_session)
    end
  end

  test "rejects an expired state token" do
    session = User.create!.sessions.create!
    token = Notion::OauthState.issue(session:)

    travel Notion::OauthState::EXPIRES_IN + 1.second do
      assert_raises Notion::OauthState::Error do
        Notion::OauthState.verify!(token:, session:)
      end
    end
  end

  test "rejects a malformed state token" do
    session = User.create!.sessions.create!

    assert_raises Notion::OauthState::Error do
      Notion::OauthState.verify!(token: "malformed", session:)
    end
  end
end
