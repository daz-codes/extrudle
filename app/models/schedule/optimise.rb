# Replans both lines around the orders' required dates (Slice 11). It works on
# a draft plan, so the planner reviews the result before publishing it.
#
#   result = Schedule::Optimise.new(PlanDraft.current.plan).call
#   result.summary #=> "2 orders late (was 5), 6 changeovers (was 9). ..."
#
# What it may change (working assumptions, PLAN.md §11 Q76–Q79):
#
# * Jobs that haven't started, for orders still to make, are re-ordered and
#   may move to the other line when their spec has a rate there.
# * Order lines with weight still to plan get a job for the rest (Q77).
# * Locked blocks never move; started jobs and other blocks the planner added
#   (maintenance, no orders) keep their place in the queue, and jobs fill the
#   places between them. "No orders" blocks go after the last job, as they
#   stand for the line having nothing to run. Changeovers are rebuilt
#   automatically, so the planner's own unlocked changeovers are dropped (Q79).
# * Urgent orders' jobs go first on their line, whatever their dates (Q78).
#
# What "best" means, in order (Q76): fewest late orders, then the fewest
# minutes late in all, then the fewest changeovers, then jobs finishing as
# early as possible. Jobs that tie on all of these come out in random order.
#
# How: jobs are taken in required-date order (urgent first, ties shuffled) and
# each goes on the line where the plan scores best. Then each job in turn is
# tried in every other place on both lines, and pairs of jobs are swapped,
# keeping any change that scores better, until nothing improves. That can stop
# short of the best plan, so it starts again from other shuffles and keeps the
# best (RUNS, within TIME_LIMIT). Times come from the same rules as
# Schedule::Reflow, with integer seconds throughout.
class Schedule::Optimise
  RUNS = 10       # fresh starts from different shuffles; the best one is kept
  TIME_LIMIT = 3 # seconds in all, however many runs that leaves

  # One job to plan: an unstarted job on the plan, or an order line's unplanned weight.
  Task = Struct.new(:block, :order_line, :planned_g, :spec_id, :urgent, :deadline, :minutes, :home_line_id, :order_id, keyword_init: true) do
    def lines = minutes.keys
  end

  # Something on a line's queue that keeps its place: a started job, maintenance, no orders.
  Fixed = Struct.new(:block, :spec_id, :minutes, keyword_init: true)

  LineState = Struct.new(:line, :anchor, :locked, :template, :trailing, :changeover_minutes, keyword_init: true)

  Score = Data.define(:late_orders, :late_minutes, :changeovers, :finish_minutes) do
    include Comparable

    def to_a = [ late_orders, late_minutes, changeovers, finish_minutes ]
    def <=>(other) = to_a <=> other.to_a
  end

  Result = Data.define(:before, :after, :added, :moved, :late_orders, :unplannable) do
    def summary
      parts = [ "#{pluralize(after.late_orders, 'order')} late (was #{before.late_orders}), " \
                "#{pluralize(after.changeovers, 'changeover')} (was #{before.changeovers})." ]
      parts << "Late: #{late_orders.join(', ')}." if late_orders.any?
      parts << "Planned #{pluralize(added, 'job')} for orders that weren't on the plan." if added.positive?
      parts << "Moved #{pluralize(moved, 'job')} to the other line." if moved.positive?
      parts << "Not planned, as no line has a rate for it: #{unplannable.join(', ')}." if unplannable.any?
      parts.join(" ")
    end

    private
      def pluralize(count, word) = "#{count} #{count == 1 ? word : word.pluralize}"
  end

  attr_reader :plan

  def initialize(plan, random: Random.new, time_limit: TIME_LIMIT)
    raise ArgumentError, "Optimise a draft plan, not the live plan" if plan.live?

    @plan = plan
    @random = random
    @time_limit = time_limit
  end

  def call
    load_plan
    before = total_score(@current)
    @time_up = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @time_limit
    best = nil
    RUNS.times do |run|
      break if run.positive? && out_of_time?

      @sequences = build_first_plan
      improve
      best = [ @best, @sequences ] if best.nil? || @best < best.first
    end
    after, @sequences = best

    ScheduleBlock.transaction { write_plan }
    Result.new(before:, after:, added: @tasks.count { _1.block.nil? }, moved: moved_count,
               late_orders: late_order_numbers(@sequences), unplannable: @unplannable)
  end

  private
    # ---- Reading the plan ------------------------------------------------

    def load_plan
      @lines = Line.active.ordered.to_a
      @states = {}
      @current = {}
      @tasks = []
      @blocks = plan.blocks.where(line: @lines).includes(:source_block, sales_order_line: [ :sales_order, { product_spec: :line_rates } ]).to_a
      @lines.each { read_line(_1) }
      add_unplanned_tasks
    end

    def read_line(line)
      blocks = @blocks.select { _1.line_id == line.id }
      locked, flowing = blocks.partition(&:locked?)
      flowing.sort_by! { [ _1.position, _1.id ] }

      template = []
      trailing = []
      current = []
      flowing.each do |block|
        next if block.changeover? # rebuilt automatically (Q79)

        if block.no_orders?
          trailing << Fixed.new(block:, spec_id: nil, minutes: block.duration_minutes) # after the last job
        elsif movable?(block)
          task = task_for_block(block, line)
          @tasks << task
          current << task
          template << :job
        else
          template << Fixed.new(block:, spec_id: block.job? ? block.product_spec&.id : nil, minutes: block.duration_minutes)
        end
      end

      anchor = plan.queue_start(line) || flowing.filter_map(&:starts_at).min || Time.current
      @states[line.id] = LineState.new(
        line:, template:, trailing:,
        anchor: Schedule.snap_up(anchor).to_i,
        locked: locked.map { [ _1.starts_at.to_i, _1.ends_at.to_i ] }.sort,
        changeover_minutes: Schedule.round_up_to_slot(line.default_changeover_minutes)
      )
      @current[line.id] = current
    end

    def movable?(block)
      block.job? && !block.started? && SalesOrder::ACTIVE_STATUSES.include?(block.sales_order.status)
    end

    def task_for_block(block, line)
      minutes = minutes_by_line(block.product_spec, block.planned_g)
      minutes[line.id] ||= block.duration_minutes # no rate here: keeps its estimate, and stays on this line
      new_task(block.sales_order_line, block.planned_g, minutes, block:, home_line_id: line.id)
    end

    # Order lines with weight still to plan get one job for the rest (Q77).
    def add_unplanned_tasks
      @unplannable = []
      plan.preload_planned!
      SalesOrderLine.joins(:sales_order).merge(SalesOrder.active)
        .includes(:sales_order, product_spec: :line_rates).order("sales_orders.required_on", :id).each do |order_line|
        unplanned = plan.unplanned_g(order_line)
        next unless unplanned.positive?

        minutes = minutes_by_line(order_line.product_spec, unplanned)
        if minutes.empty?
          @unplannable << "#{order_line.sales_order.number} #{order_line.product_spec}"
        else
          @tasks << new_task(order_line, unplanned, minutes)
        end
      end
    end

    # Lines that can make the spec: its own rate there, or the line's default (§11 Q89).
    def minutes_by_line(spec, planned_g)
      @lines.filter_map { |line| (rate = spec.kg_per_hour_on(line)) && [ line.id, Schedule.job_minutes(planned_g, rate) ] }.to_h
    end

    def new_task(order_line, planned_g, minutes, block: nil, home_line_id: nil)
      order = order_line.sales_order
      Task.new(block:, order_line:, planned_g:, minutes:, home_line_id:,
               spec_id: order_line.product_spec_id, urgent: order.urgent?, order_id: order.id,
               # Late means finishing after the end of the required day, or a week order's Friday (§11 Q16, Q90).
               deadline: order.deadline.to_i)
    end

    # ---- Scoring ---------------------------------------------------------

    # Times each block on a line as Schedule::Reflow would, with automatic
    # changeovers as Schedule::Editor builds them. Returns each task's end.
    def simulate(line_id, sequence)
      state = @states.fetch(line_id)
      cursor = state.anchor
      previous_spec = nil
      changeovers = 0
      ends = {}

      queue(state, sequence).each do |item|
        if item.is_a?(Task) || item.spec_id
          if previous_spec && previous_spec != item.spec_id && state.changeover_minutes.positive?
            cursor = place(state, cursor, state.changeover_minutes)
            changeovers += 1
          end
          previous_spec = item.spec_id
        end
        minutes = item.is_a?(Task) ? item.minutes.fetch(line_id) : item.minutes
        cursor = place(state, cursor, minutes)
        ends[item] = cursor if item.is_a?(Task)
      end
      [ ends, changeovers ]
    end

    # Jobs fill the job places in the template; extra jobs go on the end,
    # then the "no orders" blocks.
    def queue(state, sequence)
      jobs = sequence.each
      items = state.template.filter_map do |slot|
        next slot unless slot == :job

        begin
          jobs.next
        rescue StopIteration
          nil
        end
      end
      loop { items << jobs.next }
      items + state.trailing
    end

    # Starts the block at the first time it fits around locked blocks; returns its end.
    def place(state, cursor, minutes)
      length = minutes * 60
      state.locked.each do |from, to|
        cursor = to if from < cursor + length && to > cursor
      end
      cursor + length
    end

    def line_score(line_id, sequence)
      ends, changeovers = simulate(line_id, sequence)
      late = ends.select { |task, finish| finish > task.deadline }
      Score.new(
        late_orders: 0, # counted across both lines, as an order may have jobs on each
        late_minutes: late.sum { |task, finish| (finish - task.deadline) / 60 },
        changeovers:,
        finish_minutes: ends.sum { |_task, finish| (finish - @states[line_id].anchor) / 60 }
      ).then { [ _1, late.keys.map(&:order_id) ] }
    end

    def total_score(sequences) = combine(sequences.to_h { |line_id, sequence| [ line_id, line_score(line_id, sequence) ] })

    def combine(results)
      Score.new(
        late_orders: results.values.flat_map(&:last).uniq.size,
        late_minutes: results.values.sum { _1.first.late_minutes },
        changeovers: results.values.sum { _1.first.changeovers },
        finish_minutes: results.values.sum { _1.first.finish_minutes }
      )
    end

    # ---- Planning --------------------------------------------------------

    # Required-date order, urgent first, ties shuffled; each job on the line
    # where the plan scores best with it on the end.
    def build_first_plan
      sequences = @lines.to_h { [ _1.id, [] ] }
      results = sequences.to_h { |line_id, sequence| [ line_id, line_score(line_id, sequence) ] }
      ordered = @tasks.shuffle(random: @random).sort_by.with_index { |task, i| [ task.urgent ? 0 : 1, task.deadline, i ] }
      ordered.each do |task|
        trials = task.lines.map { |line_id| [ line_id, line_score(line_id, sequences[line_id] + [ task ]) ] }
        line_id, result = trials.min_by { |id, trial| [ combine(results.merge(id => trial)), @random.rand ] }
        sequences[line_id] << task
        results[line_id] = result
      end
      sequences
    end

    def improve
      @results = @sequences.to_h { |line_id, sequence| [ line_id, line_score(line_id, sequence) ] }
      @best = combine(@results)
      loop do
        improved = false
        @tasks.shuffle(random: @random).each do |task|
          break if out_of_time?

          improved |= relocate([ task ])
        end
        same_spec_runs.each do |run|
          break if out_of_time?

          improved |= relocate(run)
        end
        @tasks.combination(2).to_a.shuffle(random: @random).each do |a, b|
          break if out_of_time?

          improved |= swap(a, b)
        end
        break if !improved || out_of_time?
      end
    end

    def out_of_time? = Process.clock_gettime(Process::CLOCK_MONOTONIC) > @time_up

    # Tries a job, or a run of jobs kept together, in every allowed place on
    # every line they can all run on.
    def relocate(run)
      from = line_of(run.first)
      without = @sequences[from] - run
      lines = run.map(&:lines).reduce(:&)
      candidates = lines.flat_map do |line_id|
        base = line_id == from ? without : @sequences[line_id]
        allowed_places(base, run.first.urgent).map { |index| [ line_id, base.dup.insert(index, *run) ] }
      end
      best = candidates.shuffle(random: @random).map { |line_id, seq| [ trial(from => without, line_id => seq), line_id, seq ] }
        .min_by { _1.first.first }
      return false unless best && best.first.first < @best

      accept(best.first, from => without, best[1] => best[2])
    end

    def swap(a, b)
      line_a, line_b = line_of(a), line_of(b)
      return false unless a.lines.include?(line_b) && b.lines.include?(line_a)
      return false unless a.urgent == b.urgent # urgent jobs stay ahead of the rest

      changes = { line_a => @sequences[line_a].dup }
      changes[line_b] ||= @sequences[line_b].dup
      index_a = changes[line_a].index(a)
      index_b = changes[line_b].index(b)
      changes[line_a][index_a] = b
      changes[line_b][index_b] = a
      result = trial(changes)
      return false unless result.first < @best

      accept(result, changes)
    end

    # Runs of two or more jobs in a row for the same spec, all urgent or all not.
    def same_spec_runs
      @sequences.values.flat_map do |sequence|
        sequence.chunk_while { |a, b| a.spec_id == b.spec_id && a.urgent == b.urgent }.select { _1.size > 1 }
      end
    end

    # The plan's score with some lines changed, scoring only those lines.
    def trial(changes)
      changed = changes.to_h { |line_id, sequence| [ line_id, line_score(line_id, sequence) ] }
      [ combine(@results.merge(changed)), changed ]
    end

    def accept((score, changed), changes)
      changes.each { |line_id, sequence| @sequences[line_id] = sequence }
      @results.merge!(changed)
      @best = score
      true
    end

    # Urgent jobs go before the rest (Q78).
    def allowed_places(sequence, urgent_task)
      urgent = sequence.count(&:urgent)
      urgent_task ? (0..urgent) : (urgent..sequence.size)
    end

    def line_of(task) = @sequences.find { |_line_id, sequence| sequence.include?(task) }.first

    # ---- Writing the plan ------------------------------------------------

    def write_plan
      @lines.each do |line|
        state = @states[line.id]
        queue = queue(state, @sequences[line.id]).map { |item| item.is_a?(Task) ? block_for(item, line) : item.block }
        Schedule::Editor.new(line, plan:).rearrange(queue)
      end
    end

    # The task's own block if it stays on its line; otherwise a new job there
    # (its old block comes off the other line in that line's rearrange).
    def block_for(task, line)
      return task.block if task.block && task.home_line_id == line.id

      ScheduleBlock.new(kind: "job", sales_order_line: task.order_line, planned_g: task.planned_g,
                        notes: task.block&.notes, colour: task.block&.colour,
                        duration_minutes: task.minutes.fetch(line.id))
    end

    def moved_count
      @tasks.count { _1.block && line_of(_1) != _1.home_line_id }
    end

    def late_order_numbers(sequences)
      late_ids = sequences.flat_map { |line_id, sequence| line_score(line_id, sequence).last }.uniq
      SalesOrder.where(id: late_ids).order(:number).pluck(:number)
    end
end
