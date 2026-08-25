require "test_helper"

class LeetcodeConnectionTest < ActiveSupport::TestCase
  test "belongs to one user and stores the canonical username" do
    user = User.create!
    connection = user.create_leetcode_connection!(
      username: "  ExampleUser  ",
      tracking_started_on: Date.new(2026, 8, 24),
      verified_at: Time.utc(2026, 8, 24, 4, 30)
    )

    assert_equal user, connection.user
    assert_equal "ExampleUser", connection.username
  end

  test "allows one connection per user" do
    user = User.create!
    user.create_leetcode_connection!(connection_attributes(username: "first-user"))
    duplicate = LeetcodeConnection.new(user:, **connection_attributes(username: "second-user"))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "reserves a canonical username case insensitively" do
    User.create!.create_leetcode_connection!(connection_attributes(username: "ExampleUser"))
    duplicate = User.create!.build_leetcode_connection(connection_attributes(username: "exampleuser"))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:username], "has already been taken"
  end

  test "requires the provider identity and tracking boundary" do
    user = User.create!

    %i[username tracking_started_on verified_at].each do |attribute|
      connection = user.build_leetcode_connection(connection_attributes.merge(attribute => nil))

      assert_not connection.valid?
      assert_includes connection.errors[attribute], "can't be blank"
    end
  end

  private
    def connection_attributes(username: "exampleuser")
      {
        username:,
        tracking_started_on: Date.new(2026, 8, 24),
        verified_at: Time.utc(2026, 8, 24, 4, 30)
      }
    end
end
