# The planner's Optimise button (Slice 11): replans both lines around the
# orders' required dates, in a draft plan (started here if there isn't one) so
# the planner reviews it before publishing. See Schedule::Optimise.
class PlanOptimisationsController < ApplicationController
  require_role :admin, :office

  def create
    draft = PlanDraft.current || PlanDraft.start!(user: Current.user)
    result = Schedule::Optimise.new(draft.plan).call
    redirect_to planner_path(line: params[:line]), status: :see_other,
      notice: "Both lines are replanned in the draft. #{result.summary} Check it, then publish it, or discard it to go back to the live plan."
  rescue PlanDraft::AlreadyStarted
    retry # someone else started a draft at the same moment: optimise theirs
  rescue Schedule::Error => e
    redirect_to planner_path(line: params[:line]), status: :see_other, alert: "The plan wasn't optimised: #{e.message}"
  end
end
