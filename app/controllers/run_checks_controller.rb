class RunChecksController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_run

  def create
    return redirect_to(@run, alert: "Despatch #{@run.despatch_number} is finished, so checks can't be added.", status: :see_other) unless @run.editable?

    stage, item = params.require(:stage), params.require(:item)
    if ProductionRun::Checklist.measurement?(stage, item)
      check = @run.record_measurement(stage:, item:, actual: params[:actual], user: Current.user, note: params[:note])
      notice = check.persisted? && "#{check.label} #{check.actual} #{check.unit}: #{check.passed? ? "in tolerance" : "OUT OF TOLERANCE"}."
    else
      check = @run.record_check(stage:, item:, passed: params[:passed], user: Current.user, note: params[:note])
      notice = check.persisted? && "#{check.label}: #{check.passed? ? "yes" : "no"}."
    end

    if check.persisted?
      redirect_to run_path_at(stage), notice:, status: :see_other
    else
      redirect_to run_path_at(stage), alert: "#{ProductionRun::Checklist.label(item)} wasn't saved: #{check.errors.full_messages.to_sentence.downcase}.", status: :see_other
    end
  end

  private
    def set_run
      @run = ProductionRun.find(params[:production_run_id])
    end

    def run_path_at(stage)
      production_run_path(@run, anchor: stage)
    end
end
