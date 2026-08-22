require "test_helper"

class CleanupStaleRegistrationsJobTest < ActiveJob::TestCase
  NOW = Time.utc(2026, 8, 21, 12)
  PASSWORD = "correct horse battery staple"

  test "removes an unverified regular registration after seven days" do
    user, credential = create_registration(created_at: NOW - 7.days)

    travel_to NOW do
      assert_difference -> { User.count }, -1 do
        assert_difference -> { PasswordCredential.count }, -1 do
          CleanupStaleRegistrationsJob.perform_now
        end
      end
    end

    assert_not User.exists?(user.id)
    assert_not PasswordCredential.exists?(credential.id)
  end

  test "preserves an unverified registration younger than seven days" do
    user, credential = create_registration(created_at: NOW - 7.days + 1.second)

    travel_to NOW do
      assert_no_difference -> { User.count } do
        assert_no_difference -> { PasswordCredential.count } do
          CleanupStaleRegistrationsJob.perform_now
        end
      end
    end

    assert User.exists?(user.id)
    assert PasswordCredential.exists?(credential.id)
  end

  test "preserves a verified registration older than seven days" do
    user, credential = create_registration(
      created_at: NOW - 8.days,
      email_verified_at: NOW - 1.day
    )

    travel_to NOW do
      assert_no_difference -> { User.count } do
        assert_no_difference -> { PasswordCredential.count } do
          CleanupStaleRegistrationsJob.perform_now
        end
      end
    end

    assert User.exists?(user.id)
    assert PasswordCredential.exists?(credential.id)
  end

  test "preserves an established account with an external identity" do
    user, credential = create_registration(created_at: NOW - 8.days)
    identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "github-id"
    )

    travel_to NOW do
      assert_no_difference -> { User.count } do
        assert_no_difference -> { PasswordCredential.count } do
          CleanupStaleRegistrationsJob.perform_now
        end
      end
    end

    assert User.exists?(user.id)
    assert PasswordCredential.exists?(credential.id)
    assert ExternalIdentity.exists?(identity.id)
  end

  test "is safe to run again after removing an eligible registration" do
    create_registration(created_at: NOW - 8.days)

    travel_to NOW do
      CleanupStaleRegistrationsJob.perform_now

      assert_no_difference -> { User.count } do
        assert_no_difference -> { PasswordCredential.count } do
          CleanupStaleRegistrationsJob.perform_now
        end
      end
    end
  end

  test "rolls back the credential removal when the user cannot be destroyed" do
    user, credential = create_registration(created_at: NOW - 8.days)
    abort_destroy = -> { throw :abort }
    User.set_callback(:destroy, :before, abort_destroy)

    assert_raises ActiveRecord::RecordNotDestroyed do
      travel_to NOW do
        CleanupStaleRegistrationsJob.perform_now
      end
    end

    assert User.exists?(user.id)
    assert PasswordCredential.exists?(credential.id)
  ensure
    User.skip_callback(:destroy, :before, abort_destroy) if abort_destroy
  end

  private
    def create_registration(created_at:, email_verified_at: nil)
      travel_to created_at do
        user = User.create!
        credential = user.create_password_credential!(
          email_address: "developer-#{SecureRandom.hex(6)}@example.com",
          password: PASSWORD,
          password_confirmation: PASSWORD,
          email_verified_at:
        )

        [ user, credential ]
      end
    end
end
