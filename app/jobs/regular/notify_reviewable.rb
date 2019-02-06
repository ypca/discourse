class Jobs::NotifyReviewable < Jobs::Base

  def execute(args)
    reviewable = Reviewable.find_by(id: args[:reviewable_id])
    return unless reviewable.present?

    @contacted = Set.new

    notify_admins
    notify_moderators if reviewable.reviewable_by_moderator?
    notify_group(reviewable.reviewable_by_group) if reviewable.reviewable_by_group.present?
  end

protected

  def users
    return User if @contacted.blank?
    User.where("id NOT IN (?)", @contacted)
  end

  def notify_admins
    notify(Reviewable.pending.count, users.admins.pluck(:id))
  end

  def notify_moderators
    user_ids = users.moderators.pluck(:id)
    notify(Reviewable.pending.where(reviewable_by_moderator: true).count, user_ids)
  end

  def notify_group(group)
    @group_counts = {}
    group.users.includes(:group_users).where("users.id NOT IN (?)", @contacted).each do |u|
      reviewable_count = u.group_users.map { |gu| count_for_group(gu.group_id) }.sum
      MessageBus.publish("/reviewable_counts", { reviewable_count: reviewable_count }, user_ids: [u.id])
    end
  end

  def count_for_group(group_id)
    @group_counts[group_id] ||= Reviewable.pending.where(reviewable_by_group_id: group_id).count
  end

  def notify(count, user_ids)
    data = { reviewable_count: count }
    MessageBus.publish("/reviewable_counts", data, user_ids: user_ids)
    @contacted += user_ids
  end

end
