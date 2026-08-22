require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  setup { Current.reset }
  teardown { Current.reset }

  test "exposes the user belonging to the current session" do
    user = User.new
    Current.session = Session.new(user:)

    assert_equal user, Current.user
  end

  test "has no user when there is no current session" do
    assert_nil Current.user
  end
end
