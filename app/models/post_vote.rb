# frozen_string_literal: true

class PostVote < UserVote
  validate :validate_user_can_vote

  def self.model_creator_column
    :uploader
  end

  def validate_user_can_vote
    if score == -1 && Security::Lockdown.within_wait?(:post_downvote, user)
      errors.add(:user, "must be #{Security::Lockdown.wait_text(:post_downvote)} old to downvote posts")
      return false
    end
    allowed = user.can_post_vote_with_reason
    if allowed != true
      errors.add(:user, User.throttle_reason(allowed))
      return false
    end
    true
  end
end
