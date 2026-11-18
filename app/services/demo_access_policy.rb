# frozen_string_literal: true

# R1 restricted-demo account lifecycle policy. There is no validated production
# SMTP or email identity proof, so neither public signup nor email-based account
# recovery may be presented as operational in RAILS_ENV=production.
#
# Deliberately no ENV flag override: enabling either action requires a future
# reviewed code change and actual delivery/account-recovery acceptance.
# Development and test continue to use ordinary Devise flows.
class DemoAccessPolicy
  def self.signup_available?(environment: Rails.env)
    environment.to_s != "production"
  end

  def self.password_recovery_available?(environment: Rails.env)
    environment.to_s != "production"
  end
end
