# A line's queue start in a draft plan.
class PlanDraftLine < ApplicationRecord
  belongs_to :plan_draft
  belongs_to :line
end
