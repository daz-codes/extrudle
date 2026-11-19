# A new plan for both lines, prepared while the floor, the board's next job and
# order statuses keep using the live plan (PLAN.md Slice 7e). One at a time.
#
#   draft = PlanDraft.start!(user:)      # copies every line's live plan
#   Schedule::Editor.new(line, plan: draft.plan).move(block, :up)
#   Schedule::Publish.new(draft).call    # replaces the live plan
#   draft.discard!
class PlanDraft < ApplicationRecord
  belongs_to :started_by, class_name: "User", optional: true
  has_many :blocks, class_name: "ScheduleBlock", inverse_of: :plan_draft, dependent: :delete_all
  has_many :draft_lines, class_name: "PlanDraftLine", dependent: :delete_all

  class AlreadyStarted < StandardError; end

  def self.current = find_by(current: true)

  # Copies every line's live plan and queue start into a new draft.
  def self.start!(user: nil)
    transaction do
      raise AlreadyStarted, "A new plan is already being drafted" if exists?

      draft = create!(started_by: user)
      Line.find_each { |line| draft.draft_lines.create!(line:, queue_starts_at: line.queue_starts_at) }
      copyable = ScheduleBlock.column_names - %w[ id plan_draft_id source_block_id created_at updated_at ]
      ScheduleBlock.live.find_each do |block|
        draft.blocks.create!(block.attributes.slice(*copyable).merge("source_block_id" => block.id))
      end
      draft
    end
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyStarted, "A new plan is already being drafted"
  end

  def plan = Schedule::Plan.new(self)

  def queue_start(line) = draft_lines.find_by(line:)&.queue_starts_at

  def set_queue_start(line, time)
    draft_lines.find_or_initialize_by(line:).update!(queue_starts_at: time)
  end

  # Raises ActiveRecord::RecordNotFound if someone else published or discarded it first.
  def discard!
    transaction do
      lock!
      destroy!
    end
  end
end
