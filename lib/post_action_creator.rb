require_dependency 'post_action_result'

class PostActionCreator
  class CreateResult < PostActionResult
    attr_accessor :post_action, :reviewable
  end

  # Shortcut methods for easier invocation
  class << self
    def create(created_by, post, action_key, message: nil)
      new(created_by, post, PostActionType.types[action_key], message: message).perform
    end

    [:like, :off_topic, :spam, :inappropriate].each do |action|
      define_method(action) do |created_by, post|
        create(created_by, post, action)
      end
    end
    [:notify_moderators, :notify_user].each do |action|
      define_method(action) do |created_by, post, message = nil|
        create(created_by, post, action, message: message)
      end
    end
  end

  def initialize(
    created_by,
    post,
    post_action_type_id,
    is_warning: false,
    message: nil,
    take_action: false,
    flag_topic: false
  )
    @created_by = created_by

    @post = post
    @post_action_type_id = post_action_type_id
    @post_action_name = PostActionType.types[@post_action_type_id]

    @is_warning = is_warning
    @take_action = take_action && guardian.is_staff?

    @message = message
    @flag_topic = flag_topic
    @related_post_id = nil
  end

  def perform
    result = CreateResult.new

    unless guardian.post_can_act?(
      @post,
      @post_action_name,
      opts: {
        is_warning: @is_warning,
        taken_actions: PostAction.counts_for([@post].compact, @created_by)[@post&.id]
      }
    )
      result.forbidden = true
      result.add_error(I18n.t("invalid_access"))
      return result
    end

    PostAction.limit_action!(@created_by, @post, @post_action_type_id)

    # create related_post if needed
    if @message.present? && [:notify_moderators, :notify_user, :spam].include?(@post_action_name)
      creator = create_message_creator
      post = creator.create
      if creator.errors.present?
        result.add_errors_from(creator)
        return result
      end
      @related_post_id = post.id
    end

    begin
      post_action = create_post_action

      if post_action.blank? || post_action.errors.present?
        result.add_errors_from(post_action)
      else
        result.success = true
        result.post_action = post_action
        create_reviewable(result)
      end
    rescue ActiveRecord::RecordNotUnique
      # If the user already performed this action, it's proably due to a different browser tab
      # or non-debounced clicking. We can ignore.
      result.success = true
      result.post_action = PostAction.find_by(
        user: @created_by,
        post: @post,
        post_action_type_id: @post_action_type_id
      )
    end

    result
  end

private

  def create_post_action
    targets_topic =
      if @flag_topic && @post.topic
        @post.topic.reload.posts_count != 1
      end

    where_attrs = {
      post_id: @post.id,
      user_id: @created_by.id,
      post_action_type_id: @post_action_type_id
    }

    action_attrs = {
      staff_took_action: @take_action,
      related_post_id: @related_post_id,
      targets_topic: !!targets_topic
    }

    # First try to revive a trashed record
    post_action = PostAction.where(where_attrs)
      .with_deleted
      .where("deleted_at IS NOT NULL")
      .first

    if post_action
      post_action.recover!
      action_attrs.each { |attr, val| post_action.send("#{attr}=", val) }
      post_action.save
      PostActionNotifier.post_action_created(post_action)
    else
      post_action = PostAction.create(where_attrs.merge(action_attrs))
      if post_action && post_action.errors.count == 0
        BadgeGranter.queue_badge_grant(Badge::Trigger::PostAction, post_action: post_action)
      end
    end

    if post_action && PostActionType.notify_flag_type_ids.include?(@post_action_type_id)
      DiscourseEvent.trigger(:flag_created, post_action)
    end

    GivenDailyLike.increment_for(@created_by.id) if @post_action_type_id == PostActionType.types[:like]

    # agree with other flags
    if @take_action
      PostAction.agree_flags!(@post, @created_by)
      post_action.try(:update_counters)
    end

    post_action
  rescue ActiveRecord::RecordNotUnique
    # can happen despite being .create
    # since already bookmarked
    PostAction.where(where_attrs).first
  end

  def create_message_creator
    title = I18n.t(
      "post_action_types.#{@post_action_name}.email_title",
      title: @post.topic.title,
      locale: SiteSetting.default_locale
    )

    body = I18n.t(
      "post_action_types.#{@post_action_name}.email_body",
      message: @message,
      link: "#{Discourse.base_url}#{@post.url}",
      locale: SiteSetting.default_locale
    )

    create_args = {
      archetype: Archetype.private_message,
      is_warning: @is_warning,
      title: title.truncate(SiteSetting.max_topic_title_length, separator: /\s/),
      raw: body
    }

    if [:notify_moderators, :spam].include?(@post_action_name)
      create_args[:subtype] = TopicSubtype.notify_moderators
      create_args[:target_group_names] = Group[:moderators].name
    else
      create_args[:subtype] = TopicSubtype.notify_user

      create_args[:target_usernames] =
        if @post_action_name == :notify_user
          @post.user.username
        elsif @post_action_name != :notify_moderators
          # this is a hack to allow a PM with no recipients, we should think through
          # a cleaner technique, a PM with myself is valid for flagging
          'x'
        end
    end

    PostCreator.new(@created_by, create_args)
  end

  def create_reviewable(result)
    return unless PostActionType.notify_flag_type_ids.include?(@post_action_type_id)

    result.reviewable = ReviewableFlaggedPost.needs_review!(
      created_by: @created_by,
      target: @post,
      reviewable_by_moderator: true
    )
    result.reviewable.add_score(@created_by, @post_action_type_id)
  end

  def guardian
    @guardian ||= Guardian.new(@created_by)
  end

end
