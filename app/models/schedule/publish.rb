# Replaces the live plan with a draft, in one transaction (PLAN.md Slice 7e).
#
# Draft blocks copied from a live block update that block in place, so a started
# job keeps its production log. New draft blocks are added, and live blocks the
# draft dropped are removed, except a started job, which stays on the plan.
# Started jobs go ahead of every job not started yet: they're running or done,
# even if the draft had moved one before it started. Then each line takes the
# draft's queue start and is reflowed, and order statuses are refreshed.
#
# Before publishing, #notes says what happened in reality since the draft
# began and what publishing does about it. Working assumption, see PLAN.md §11 Q55.
#
#   publish = Schedule::Publish.new(PlanDraft.current)
#   publish.notes      # => ["Despatch 732 started on line D2 after the draft began. ..."]
#   publish.changes    # => [#<LineChange line=D1 added=2 removed=1 retimed=5>, ...]
#   publish.call
class Schedule::Publish
  COPIED = (ScheduleBlock.column_names - %w[ id plan_draft_id source_block_id created_at updated_at ]).freeze
  COMPARED = %w[ kind starts_at duration_minutes planned_g locked notes ].freeze

  LineChange = Data.define(:line, :added, :removed, :changed) do
    def any? = (added + removed + changed).positive?
  end

  attr_reader :draft

  def initialize(draft)
    @draft = draft
  end

  # What happened in reality since the draft began, and what publishing does about it.
  def notes
    started_notes + cancelled_notes + added_notes
  end

  # Per line: blocks the draft adds, removes and changes, compared with the live plan.
  def changes
    lines.map do |line|
      live = line.schedule_blocks.to_a.index_by(&:id)
      drafted = draft_blocks(line)
      sources = drafted.filter_map(&:source_block_id)
      LineChange.new(
        line:,
        added: drafted.count { _1.source_block_id.nil? || !live.key?(_1.source_block_id) },
        removed: live.values.count { !sources.include?(_1.id) },
        changed: drafted.count { (live_block = live[_1.source_block_id]) && differs?(_1, live_block) }
      )
    end
  end

  def call
    orders = Set.new
    ScheduleBlock.transaction do
      draft.lock!
      lines.each { publish_line(_1, orders) }
      draft.destroy!
      orders.each { _1.reload.refresh_schedule_status! }
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    raise Schedule::Error, "#{e.record}: #{e.record.errors.full_messages.to_sentence}"
  end

  private
    def lines
      @lines ||= Line.where(id: draft.blocks.select(:line_id)).or(Line.where(id: ScheduleBlock.live.select(:line_id)))
        .or(Line.where(id: draft.draft_lines.where.not(queue_starts_at: nil).select(:line_id))).ordered.to_a
    end

    def draft_blocks(line)
      draft.blocks.where(line:).includes(sales_order_line: :sales_order).order(:position).to_a
    end

    def publish_line(line, orders)
      drafted = draft_blocks(line)
      sources = drafted.filter_map(&:source_block_id)

      # Locked blocks are saved one at a time below; unlock them first so a
      # block moving onto another's old slot doesn't clash for a moment. Load
      # them after, so saving the draft's "locked" really writes it back.
      line.schedule_blocks.update_all(locked: false)
      live = line.schedule_blocks.includes(:production_run, :sales_order_line).to_a.index_by(&:id)

      live.each_value do |block|
        next if sources.include?(block.id)

        orders << block.sales_order if block.job?
        if block.started?
          next # stays on the plan; put ahead of jobs not started below
        else
          block.destroy!
        end
      end

      drafted.each do |copy|
        next if copy.job? && !SalesOrder::ACTIVE_STATUSES.include?(copy.sales_order.status)

        block = live[copy.source_block_id] || ScheduleBlock.new
        block.assign_attributes(copy.attributes.slice(*COPIED))
        block.save!
        orders << block.sales_order if block.job?
      end

      started_jobs_first(line)
      editor = Schedule::Editor.new(line)
      (start = draft.queue_start(line)) ? editor.start_at(start) : editor.reflow
    end

    # Reorders the line's queue (unlocked blocks) so started jobs come before
    # everything not started yet, keeping the order within each group.
    def started_jobs_first(line)
      queue = line.schedule_blocks.reload.includes(:production_run).reject(&:locked?).sort_by { [ _1.position || 0, _1.id ] }
      started, rest = queue.partition(&:started?)
      (started + rest).each.with_index(1) { |block, index| block.update_columns(position: index) if block.position != index }
    end

    def differs?(copy, live_block)
      COMPARED.any? { copy[_1] != live_block[_1] }
    end

    def started_notes
      ProductionRun.where(started_at: draft.created_at..).or(ProductionRun.where(created_at: draft.created_at..))
        .includes(:line, sales_order_line: :sales_order).order(:started_at).map do |run|
        on_draft = run.schedule_block_id && draft.blocks.exists?(source_block_id: run.schedule_block_id)
        "Despatch #{run.despatch_number} (#{run.sales_order.number} #{run.product_spec}) started on line #{run.line.name} after the draft began. " +
          (on_draft ? "It has started, so it goes ahead of the jobs not started yet in the new plan." : "The draft took it off, but it has started, so it stays on the plan, ahead of the jobs not started yet.")
      end
    end

    def cancelled_notes
      SalesOrder.cancelled.where(updated_at: draft.created_at..).order(:number).map do |order|
        "#{order.number} was cancelled after the draft began. Its jobs are off both plans."
      end
    end

    def added_notes
      plan = draft.plan.preload_planned!
      SalesOrderLine.joins(:sales_order).merge(SalesOrder.active).where(created_at: draft.created_at..)
        .includes(:sales_order, :product_spec).select { plan.unplanned_g(_1).positive? }.map do |order_line|
        "#{order_line.sales_order.number} #{order_line.product_spec} was added after the draft began and isn't fully on it. " \
          "It stays under Orders to plan."
      end
    end
end
