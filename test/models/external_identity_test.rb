require "test_helper"

class ExternalIdentityTest < ActiveSupport::TestCase
  test "belongs to a Gridfolio user and stores the provider UID as an opaque string" do
    user = User.create!
    identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "42",
      provider_username: "octocat"
    )

    assert_equal user, identity.user
    assert_equal "42", identity.provider_uid
    assert_equal "octocat", identity.provider_username
  end

  test "one provider account cannot belong to two Gridfolio users" do
    first_user = User.create!
    second_user = User.create!
    first_user.external_identities.create!(
      provider: "github",
      provider_uid: "42"
    )
    duplicate = second_user.external_identities.build(
      provider: "github",
      provider_uid: "42"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider_uid], "has already been taken"
  end

  test "a user can have only one identity for a provider" do
    user = User.create!
    user.external_identities.create!(provider: "github", provider_uid: "first")
    duplicate = user.external_identities.build(provider: "github", provider_uid: "second")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider], "has already been taken"
  end

  test "rejects an unsupported provider" do
    identity = User.create!.external_identities.build(
      provider: "unknown",
      provider_uid: "provider-id"
    )

    assert_not identity.valid?
    assert_includes identity.errors[:provider], "is not included in the list"
  end

  test "database uniqueness protects the provider account ownership boundary" do
    first_user = User.create!
    second_user = User.create!
    first_user.external_identities.create!(provider: "github", provider_uid: "shared-id")

    assert_raises ActiveRecord::RecordNotUnique do
      ExternalIdentity.insert!({
        user_id: second_user.id,
        provider: "github",
        provider_uid: "shared-id",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end
end
