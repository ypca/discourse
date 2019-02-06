require_dependency 'queued_post_serializer'

class QueuedPostsController < ApplicationController

  before_action :ensure_staff

  def index
    Discourse.deprecate("QueuedPostController#index is deprecated. Please use the Reviewable API instead.")

    status = params[:state] || 'pending'
    status = 'pending' if status == 'new'

    reviewables = Reviewable.list_for(current_user, status: status.to_sym, type: 'ReviewableQueuedPost')
    render_serialized(reviewables,
                      QueuedPostSerializer,
                      root: :queued_posts,
                      rest_serializer: true,
                      refresh_queued_posts: "/queued_posts?status=new")
  end

  def update
    Discourse.deprecate("QueuedPostController#update is deprecated. Please use the Reviewable API instead.")
    reviewable = Reviewable.find_by(id: params[:id])
    raise Discourse::NotFound if reviewable.blank?

    update_params = params[:queued_post]

    reviewable.payload['raw'] = update_params[:raw] if update_params[:raw].present?
    if reviewable.topic_id.blank? && params[:queued_post][:state].blank?
      reviewable.payload['title'] = update_params[:title] if update_params[:title].present?
      reviewable.payload['tags'] = update_params[:tags]
      reviewable.category_id = update_params[:category_id].to_i if update_params[:category_id].present?
    end

    reviewable.save(validate: false)

    state = params[:queued_post][:state]
    begin
      if state == 'approved'
        reviewable.perform(current_user, :approve)
      elsif state == 'rejected'
        reviewable.perform(current_user, :reject)
        if params[:queued_post][:delete_user] == 'true' && guardian.can_delete_user?(reviewable.created_by)
          UserDestroyer.new(current_user).destroy(reviewable.created_by, user_deletion_opts)
        end
      end
    rescue StandardError => e
      return render_json_error e.message
    end

    render_serialized(reviewable, QueuedPostSerializer, root: :queued_posts)
  end

  private

  def user_deletion_opts
    base = {
      context: I18n.t('queue.delete_reason', performed_by: current_user.username),
      delete_posts: true,
      delete_as_spammer: true
    }

    if Rails.env.production? && ENV["Staging"].nil?
      base.merge!(block_email: true, block_ip: true)
    end

    base
  end

end
