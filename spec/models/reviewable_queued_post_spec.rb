require 'rails_helper'

RSpec.describe ReviewableQueuedPost, type: :model do

  let!(:category) { Fabricate(:category) }
  let(:moderator) { Fabricate(:moderator) }

  context "creating a post" do
    let!(:topic) { Fabricate(:topic, category: category) }
    let(:reviewable) { Fabricate(:reviewable_queued_post, topic: topic) }

    context "create" do
      it "triggers queued_post_created" do
        event = DiscourseEvent.track(:queued_post_created) { reviewable.save! }
        expect(event).to be_present
        expect(event[:params][0]).to eq(reviewable)
      end

      it "returns the appropriate create options" do
        create_options = reviewable.create_options

        expect(create_options[:topic_id]).to eq(topic.id)
        expect(create_options[:raw]).to eq('hello world post contents.')
        expect(create_options[:reply_to_post_number]).to eq(1)
        expect(create_options[:via_email]).to eq(true)
        expect(create_options[:raw_email]).to eq('store_me')
        expect(create_options[:auto_track]).to eq(true)
        expect(create_options[:custom_fields]).to eq('hello' => 'world')
        expect(create_options[:cooking_options]).to eq(cat: 'hat')
        expect(create_options[:cook_method]).to eq(Post.cook_methods[:raw_html])
        expect(create_options[:not_create_option]).to eq(nil)
        expect(create_options[:image_sizes]).to eq("http://foo.bar/image.png" => { "width" => 0, "height" => 222 })
      end
    end

    context "actions" do

      context "approve" do
        it 'triggers an extensibility event' do
          event = DiscourseEvent.track(:approved_post) { reviewable.perform(moderator, :approve) }
          expect(event).to be_present
          expect(event[:params].first).to eq(reviewable)
        end

        it "creates a post" do
          topic_count, post_count = Topic.count, Post.count
          result = reviewable.perform(moderator, :approve)
          expect(result.success?).to eq(true)
          expect(result.created_post).to be_present
          expect(result.created_post).to be_valid
          expect(result.created_post.topic).to eq(topic)
          expect(result.created_post.custom_fields['hello']).to eq('world')
          expect(result.created_post_topic).to eq(topic)
          expect(reviewable.payload['created_post_id']).to eq(result.created_post.id)

          expect(Topic.count).to eq(topic_count)
          expect(Post.count).to eq(post_count + 1)

          # We can't approve twice
          expect(-> { reviewable.perform(moderator, :approve) }).to raise_error(Reviewable::InvalidAction)
        end

        it "skips validations" do
          reviewable.payload['raw'] = 'x'
          result = reviewable.perform(moderator, :approve)
          expect(result.created_post).to be_present
        end
      end

      context "reject" do
        it 'triggers an extensibility event' do
          event = DiscourseEvent.track(:rejected_post) { reviewable.perform(moderator, :reject) }
          expect(event).to be_present
          expect(event[:params].first).to eq(reviewable)
        end

        it "doesn't create a post" do
          post_count = Post.count
          result = reviewable.perform(moderator, :reject)
          expect(result.success?).to eq(true)
          expect(result.created_post).to be_nil
          expect(Post.count).to eq(post_count)

          # We can't reject twice
          expect(-> { reviewable.perform(moderator, :reject) }).to raise_error(Reviewable::InvalidAction)
        end
      end

      context "delete_user" do
        it "deletes the user and rejects the post" do
          other_reviewable = Fabricate(:reviewable_queued_post, created_by: reviewable.created_by)

          result = reviewable.perform(moderator, :delete_user)
          expect(result.success?).to eq(true)
          expect(User.find_by(id: reviewable.created_by)).to be_blank
          expect(result.remove_reviewable_ids).to include(reviewable.id)
          expect(result.remove_reviewable_ids).to include(other_reviewable.id)

          expect(ReviewableQueuedPost.where(id: reviewable.id)).to be_blank
          expect(ReviewableQueuedPost.where(id: other_reviewable.id)).to be_blank
        end
      end
    end
  end

  context "creating a topic" do
    let(:reviewable) { Fabricate(:reviewable_queued_post_topic, category: category) }

    context "editing" do
      let(:guardian) { Guardian.new(moderator) }

      it "is editable and returns the fields" do
        fields = reviewable.editable_for(guardian)
        expect(fields.has?('category_id')).to eq(true)
        expect(fields.has?('payload.raw')).to eq(true)
        expect(fields.has?('payload.title')).to eq(true)
        expect(fields.has?('payload.tags')).to eq(true)
      end
    end

    it "returns the appropriate create options for a topic" do
      create_options = reviewable.create_options
      expect(create_options[:category]).to eq(reviewable.category.id)
      expect(create_options[:archetype]).to eq('regular')
    end

    it "creates the post and topic when approved" do
      topic_count, post_count = Topic.count, Post.count
      result = reviewable.perform(moderator, :approve)

      expect(result.success?).to eq(true)
      expect(result.created_post).to be_present
      expect(result.created_post).to be_valid
      expect(result.created_post_topic).to be_present
      expect(result.created_post_topic).to be_valid
      expect(reviewable.payload['created_post_id']).to eq(result.created_post.id)
      expect(reviewable.payload['created_topic_id']).to eq(result.created_post_topic.id)

      expect(Topic.count).to eq(topic_count + 1)
      expect(Post.count).to eq(post_count + 1)
    end

    it "creates the post and topic when rejected" do
      topic_count, post_count = Topic.count, Post.count
      result = reviewable.perform(moderator, :reject)

      expect(result.success?).to eq(true)
      expect(result.created_post).to be_blank
      expect(result.created_post_topic).to be_blank

      expect(Topic.count).to eq(topic_count)
      expect(Post.count).to eq(post_count)
    end
  end
end
