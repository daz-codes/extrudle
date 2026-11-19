# Draft plans (PLAN.md Slice 7e): start one from the live plan, review what
# publishing will do, publish it, or discard it. Anyone who can use the
# planner can do all three (working assumption, PLAN.md §11 Q53).
class PlanDraftsController < ApplicationController
  require_role :admin, :office
  before_action :set_draft, only: %i[ show destroy publish ]

  # The review page before publishing.
  def show
    @publish = Schedule::Publish.new(@draft)
  end

  def create
    PlanDraft.start!(user: Current.user)
    redirect_to planner_path(line: params[:line]), notice: "New plan started from the live plan. The floor keeps using the live plan until you publish."
  rescue PlanDraft::AlreadyStarted => e
    redirect_to planner_path(line: params[:line]), alert: "#{e.message}. Carry on with it, or discard it first."
  end

  def destroy
    @draft.discard!
    redirect_to planner_path(line: params[:line]), notice: "The draft plan was discarded. The live plan is unchanged.", status: :see_other
  end

  def publish
    Schedule::Publish.new(@draft).call
    redirect_to planner_path(line: params[:line]), notice: "The new plan is live.", status: :see_other
  rescue Schedule::Error => e
    redirect_to plan_draft_path, alert: "The plan wasn't published: #{e.message}", status: :see_other
  end

  private
    def set_draft
      @draft = PlanDraft.current
      redirect_to planner_path, alert: "There's no draft plan." unless @draft
    end
end
