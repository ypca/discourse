%i(
  topic_recovered
).each do |event|
  DiscourseEvent.on(event) do |topic, _|
    WebHook.enqueue_topic_hooks(event, topic)
  end
end

DiscourseEvent.on(:topic_status_updated) do |topic, status|
  WebHook.enqueue_topic_hooks("topic_#{status}_status_updated", topic)
end

DiscourseEvent.on(:topic_created) do |topic, _, _|
  WebHook.enqueue_topic_hooks(:topic_created, topic)
end

%i(
  post_created
  post_recovered
).each do |event|
  DiscourseEvent.on(event) do |post, _, _|
    WebHook.enqueue_post_hooks(event, post)
  end
end

DiscourseEvent.on(:post_edited) do |post, topic_changed|
  if post.topic
    WebHook.enqueue_post_hooks(:post_edited, post)

    if post.is_first_post? && topic_changed
      WebHook.enqueue_topic_hooks(:topic_edited, post.topic)
    end
  end
end

%i(
  user_logged_out
  user_created
  user_logged_in
  user_approved
  user_updated
).each do |event|
  DiscourseEvent.on(event) do |user|
    WebHook.enqueue_object_hooks(:user, user, event)
  end
end

%i(
  group_created
  group_updated
).each do |event|
  DiscourseEvent.on(event) do |group|
    WebHook.enqueue_object_hooks(:group, group, event)
  end
end

%i(
  category_created
  category_updated
).each do |event|
  DiscourseEvent.on(event) do |category|
    WebHook.enqueue_object_hooks(:category, category, event)
  end
end

%i(
  tag_created
  tag_updated
).each do |event|
  DiscourseEvent.on(event) do |tag|
    WebHook.enqueue_object_hooks(:tag, tag, event, TagSerializer)
  end
end

%i(
  flag_created
  flag_agreed
  flag_disagreed
  flag_deferred
).each do |event|
  DiscourseEvent.on(event) do |flag|
    WebHook.enqueue_object_hooks(:flag, flag, event)
  end
end

DiscourseEvent.on(:reviewable_created) do |reviewable|
  WebHook.enqueue_object_hooks(:reviewable, reviewable, :reviewable_created, reviewable.serializer)

  # TODO: Backwards compatibility for Queued Post webhooks. Remve in favor of Reviewable API
  if reviewable.is_a?(ReviewableQueuedPost)
    WebHook.enqueue_object_hooks(:queued_post, reviewable, :queued_post_created, reviewable.serializer)
  end
end

DiscourseEvent.on(:reviewable_transitioned_to) do |status, reviewable|
  WebHook.enqueue_object_hooks(:reviewable, reviewable, :reviewable_transitioned_to, reviewable.serializer)

  # TODO: Backwards compatibility for Queued Post webhooks. Remve in favor of Reviewable API
  if reviewable.is_a?(ReviewableQueuedPost)
    if reviewable.approved?
      WebHook.enqueue_object_hooks(:queued_post, reviewable, :approved_post, QueuedPostSerializer)
    elsif reviewable.rejected?
      WebHook.enqueue_object_hooks(:queued_post, reviewable, :rejected_post, QueuedPostSerializer)
    end
  end
end
