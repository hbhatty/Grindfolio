class CleanupStaleRegistrationsJob < ApplicationJob
  STALE_REGISTRATION_AGE = 7.days
  BATCH_SIZE = 1_000

  def perform
    cutoff = STALE_REGISTRATION_AGE.ago

    eligible_credentials(cutoff:).find_each(batch_size: BATCH_SIZE) do |credential|
      destroy_registration_if_still_eligible(credential.id, cutoff:)
    end
  end

  private
    def eligible_credentials(cutoff:)
      PasswordCredential.where(email_verified_at: nil, created_at: ..cutoff)
    end

    def destroy_registration_if_still_eligible(credential_id, cutoff:)
      PasswordCredential.transaction do
        credential = eligible_credentials(cutoff:).lock.find_by(id: credential_id)
        next unless credential

        User.lock.find(credential.user_id).destroy!
      end
    end
end
