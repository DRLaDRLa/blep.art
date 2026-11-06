# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  include_context "as admin"

  before do
    Security::Lockdown::WAIT_LIMITS.each { |key, limit| Security::Lockdown.set_wait_hours(key, limit[:default]) }
  end

  describe "new account wait limits" do
    it "uses the old hard-coded values as defaults" do
      defaults = Security::Lockdown::WAIT_LIMITS.transform_values { |limit| limit[:default] }
      expect(defaults.values_at(:upload, :post_edit, :comment, :dmail)).to all(eq(168))
      expect(defaults.values_at(:forum_post, :note_edit, :post_flag, :ticket)).to all(eq(72))
    end

    it "blocks an action inside its wait" do
      newbie = create(:user, created_at: 1.day.ago)
      expect(newbie.can_comment_with_reason).to eq(:REJ_NEWBIE)
    end

    it "allows the action once the wait is shorter than the account's age" do
      Security::Lockdown.set_wait_hours(:comment, 12)
      newbie = create(:user, created_at: 1.day.ago)
      expect(newbie.can_comment_with_reason).not_to eq(:REJ_NEWBIE)
    end

    it "has no wait when set to 0 hours" do
      Security::Lockdown.set_wait_hours(:forum_post, 0)
      newbie = create(:user, created_at: 1.minute.ago)
      expect(newbie.can_forum_post_with_reason).not_to eq(:REJ_NEWBIE)
    end

    it "applies one DMail wait to the per-minute, hourly and daily DMail throttles" do
      Security::Lockdown.set_wait_hours(:dmail, 0)
      newbie = create(:user, created_at: 1.minute.ago)
      expect([newbie.can_dmail_minute_with_reason, newbie.can_dmail_with_reason, newbie.can_dmail_day_with_reason]).not_to include(:REJ_NEWBIE)
    end

    it "applies one report wait to both tickets and appeals" do
      newbie = create(:user, created_at: 1.day.ago)
      expect([newbie.can_ticket_hourly_with_reason, newbie.can_appeal_hourly_with_reason]).to all(eq(:REJ_NEWBIE))
    end

    it "blocks uploads from an account younger than the upload wait" do
      newbie = create(:user, created_at: 2.days.ago)
      expect(newbie.can_upload_with_reason).to eq(:REJ_UPLOAD_NEWBIE)
    end

    it "waits the configured hours before a new account can downvote posts" do
      newbie = create(:user, created_at: 2.days.ago)
      vote = build(:post_vote, user: newbie, score: -1)
      expect(vote).not_to be_valid
      expect(vote.errors.full_messages.join).to include("must be 3 days old to downvote posts")

      Security::Lockdown.set_wait_hours(:post_downvote, 24)
      vote = build(:post_vote, user: newbie, score: -1)
      vote.valid?
      expect(vote.errors.full_messages.grep(/downvote/)).to be_empty
    end

    it "waits the configured hours before a new account can make a set public" do
      newbie = create(:user, created_at: 2.days.ago)
      set = build(:public_post_set, creator: newbie)
      expect(set).not_to be_valid
      expect(set.errors.full_messages.join).to include("at least 3 days old")

      Security::Lockdown.set_wait_hours(:set_public, 36)
      set = build(:public_post_set, creator: newbie)
      set.valid?
      expect(set.errors.full_messages.grep(/public/)).to be_empty
    end

    it "has no upload wait when it is set to 0 hours" do
      Security::Lockdown.upload_wait_hours = 0
      newbie = create(:user, created_at: 1.minute.ago)
      expect(newbie.can_upload_with_reason).not_to eq(:REJ_UPLOAD_NEWBIE)
    end
  end
end
