class ReviewableHistory < ActiveRecord::Base
  belongs_to :reviewable
  belongs_to :created_by, class_name: 'User'

  def self.types
    @types ||= Enum.new(
      created: 0,
      transitioned: 1,
      edited: 2
    )
  end

end

# == Schema Information
#
# Table name: reviewable_histories
#
#  id                      :bigint(8)        not null, primary key
#  reviewable_id           :integer          not null
#  reviewable_history_type :integer          not null
#  status                  :integer          not null
#  created_by_id           :integer          not null
#  edited                  :json
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_reviewable_histories_on_reviewable_id  (reviewable_id)
#
