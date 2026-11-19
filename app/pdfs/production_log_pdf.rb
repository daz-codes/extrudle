# A production log printed like paper form 5.4.1.2, for audits and ISO records.
# A4 portrait. Page 1 is the job, checks and materials; the reel sheet starts
# on page 2 as on the paper form, then the end of run and sign-off.
#
# A log that's still running prints with an "in progress" warning on every page.
# Working assumptions, see PLAN.md §11 Q59–Q62.
class ProductionLogPdf
  include PdfFormatting

  FOOTER_HEIGHT = 20
  FORM = "Form 5.4.1.2"

  def initialize(run, printed_by: nil, printed_at: Time.current)
    @run = run
    @printed_by = printed_by
    @printed_at = printed_at
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 36, 36, 36 + FOOTER_HEIGHT, 36 ], info: { Title: title, Creator: "Extrudle" })
    pdf.font "Helvetica"
    pdf.font_size 9
    pdf.fill_color INK

    header(pdf)
    job(pdf)
    batches(pdf)
    instructions(pdf)
    yes_no(pdf, "prestart", "Prestart checks")
    readings(pdf, "startup", "Width and thickness at start-up")
    materials(pdf)

    pdf.start_new_page
    section(pdf, "Reels")
    reels(pdf)
    readings(pdf, "end_of_run", "Width and thickness at the end of the run")
    yes_no(pdf, "line_clearance", "Line clearance")
    comments(pdf)
    sign_off(pdf)
    footer(pdf)
    pdf.render
  end

  def filename = "despatch-#{run.despatch_number}#{"-in-progress" if run.running?}.pdf"

  private
    attr_reader :run

    def title = "Production log, despatch #{run.despatch_number}"

    def helpers = ApplicationController.helpers

    def header(pdf)
      top = pdf.cursor
      pdf.bounding_box([ 0, top ], width: pdf.bounds.width - 150) do
        pdf.text text(Company.name), size: 9, color: MUTED
        pdf.text "PRODUCTION LOG", size: 18, style: :bold
        pdf.text "#{FORM} · Line #{text(run.line.name)}", color: MUTED
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([ pdf.bounds.width - 140, top ], width: 140, height: 52) do
        pdf.stroke_color INK
        pdf.line_width 1.5
        pdf.stroke_bounds
        pdf.move_down 6
        pdf.text "DESPATCH No.", size: 7, style: :bold, color: MUTED, align: :center
        pdf.text run.despatch_number.to_s, size: 22, style: :bold, align: :center
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
      pdf.move_down 8

      if run.running?
        pdf.fill_color BAD
        pdf.text "IN PROGRESS: printed #{date_time(@printed_at)}. Not the final record.", style: :bold
        pdf.fill_color INK
        pdf.move_down 6
      end
    end

    def job(pdf)
      fields = helpers.run_header_fields(run).merge(
        "Started" => date_time(run.started_at),
        "Ended" => run.finished? ? date_time(run.ended_at) : "Running"
      )
      field_grid(pdf, fields)
    end

    def batches(pdf)
      field_grid(pdf, {
        "Antiblock batch" => run.antiblock_batch_no, "Silicone batch" => run.silicone_batch_no,
        "PE film batch" => run.pe_film_batch_no, "Technician (days)" => run.technician_days,
        "Technician (nights)" => run.technician_nights
      }.transform_values { _1 || "—" })
    end

    def instructions(pdf)
      return if run.special_instructions.blank?

      section(pdf, "Special instructions")
      pdf.text text(run.special_instructions)
      pdf.move_down 10
    end

    def yes_no(pdf, stage, heading)
      section(pdf, heading)
      rows = ProductionRun::Checklist.items(stage).map do |item, label|
        check = run.answer(stage, item)
        answer = if check.nil? then { content: "Not answered", text_color: MUTED }
        else { content: check.passed? ? "Yes" : "No", text_color: check.passed? ? OK : BAD, font_style: :bold }
        end
        [ label, answer, text(check&.user&.name || "—"), date_time(check&.checked_at), text(check&.note.to_s) ]
      end
      grid(pdf, [ "Check", "Answer", "By", "When", "Note" ], rows, column_widths: { 0 => 190, 1 => 70, 2 => 90, 3 => 85 })
    end

    def readings(pdf, stage, heading)
      section(pdf, heading)
      checks = ProductionRun::Checklist::MEASUREMENTS.keys.flat_map { run.measurements(_1, stage:) }.sort_by(&:checked_at)
      rows = checks.map do |check|
        [ check.label, "#{check.target} #{check.unit}", "#{check.min_value}–#{check.max_value} #{check.unit}",
          { content: "#{check.actual} #{check.unit}", font_style: :bold },
          { content: check.passed? ? "Pass" : "Fail", text_color: check.passed? ? OK : BAD, font_style: :bold },
          text(check.user&.name || "—"), date_time(check.checked_at) ]
      end
      rows = [ [ { content: "No readings recorded.", colspan: 7, text_color: MUTED } ] ] if rows.empty?
      grid(pdf, [ "Reading", "Target", "Passes", "Actual", "Result", "By", "When" ], rows)
    end

    def materials(pdf)
      section(pdf, "Materials loaded")
      used = used_by_lot
      shown = Set.new
      loads = run.material_loads.sort_by { [ MaterialLoad::FEEDS.keys.index(_1.feed), _1.from_reel_no, _1.id ] }
      rows = loads.map do |load|
        lot = load.lot
        grams = used[lot.id] if shown.add?(lot.id)
        [ load.feed_label, text(lot.material.name), text(lot.supplier_lot_ref || "—"), text(lot.bag_no || "—"), lot.code,
          helpers.reel_range_text(run.reel_range(load)), text(load.initials || "—"), grams ? kg_number(grams) : "" ]
      end
      rows = [ [ { content: "No bags recorded.", colspan: 8, text_color: MUTED } ] ] if rows.empty?
      used_heading = run.finished? ? "Used (kg)" : "Used so far, est. (kg)"
      grid(pdf, [ "Feed", "Material", "Supplier batch", "Bag", "Lot", "Reels", "Initials", used_heading ], rows,
           right: [ 7 ], column_widths: { 4 => 78, 7 => 70 })
    end

    # { lot_id => grams }: what was posted for a finished log, else the estimate so far.
    def used_by_lot
      if run.finished?
        run.consumptions.group_by(&:lot_id).transform_values { -_1.sum(&:quantity_g) }
      else
        run.material_use.by_lot.transform_keys(&:id)
      end
    end

    def reels(pdf)
      running = 0
      rows = run.reels.map do |reel|
        running += reel.weight_g
        [ reel.reel_no.to_s, date_time(reel.produced_at), kg_number(reel.weight_g),
          reel.length_m ? number_with_delimiter(reel.length_m) : "—", reel.pallet_no&.to_s || "—",
          text(reel.initials || "—"), kg_number(running) ]
      end
      if rows.empty?
        rows = [ [ { content: "No reels entered.", colspan: 7, text_color: MUTED } ] ]
      else
        rows << [ { content: "#{run.reels.size} reels · #{run.percent_of_order}% of #{quantity(run.order_quantity_g)} ordered", colspan: 6, font_style: :bold, align: :left },
                  { content: kg_number(run.total_g), font_style: :bold } ]
      end
      grid(pdf, [ "Reel", "Time", "Weight (kg)", "Length (m)", "Pallet", "Initials", "Running total (kg)" ], rows,
           right: [ 0, 2, 3, 4, 6 ], total_row: run.reels.any?)
    end

    def comments(pdf)
      section(pdf, "Comments and corrective actions")
      pdf.text text(run.comments.presence || "None.")
      pdf.move_down 12
    end

    # Who started and finished the log in the app, plus lines to sign a
    # printed copy. Working assumption, see PLAN.md §11 Q60.
    def sign_off(pdf)
      section(pdf, "Sign-off")
      field_grid(pdf, {
        "Started by" => "#{run.started_by&.name || "—"}, #{date_time(run.started_at)}",
        "Finished by" => run.finished? ? "#{run.finished_by&.name || "—"}, #{date_time(run.ended_at)}" : "Still running",
        "No. of deliveries" => "—"
      }, per_row: 3)
      pdf.move_down 18
      width = (pdf.bounds.width - 24) / 2
      [ "Technician", "Checked by (QA)" ].each_with_index do |label, index|
        x = index * (width + 24)
        pdf.stroke_color INK
        pdf.line_width 0.5
        pdf.stroke_horizontal_line x, x + width, at: pdf.cursor
        pdf.draw_text "#{label}: signature and date", at: [ x, pdf.cursor - 10 ], size: 7
      end
      pdf.move_down 16
    end

    def footer(pdf)
      left = [ "Despatch #{run.despatch_number}", FORM, "Printed #{date_time(@printed_at)}#{" by #{@printed_by.name}" if @printed_by}" ]
      left << "IN PROGRESS" if run.running?
      pdf.repeat(:all) do
        pdf.bounding_box([ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width * 0.8, height: 12) do
          pdf.text text(left.join("  ·  ")), size: 7, color: run.running? ? BAD : MUTED
        end
      end
      pdf.number_pages "Page <page> of <total>", at: [ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width, align: :right, size: 7, color: MUTED
    end

    # Small-caps heading with a rule, kept with at least the next few lines.
    def section(pdf, heading)
      pdf.start_new_page if pdf.cursor < 80
      pdf.move_down 4
      pdf.text heading.upcase, size: 8, style: :bold, color: MUTED
      pdf.move_down 3
    end

    # Label-over-value boxes, five to a row, like the boxes at the top of the paper form.
    def field_grid(pdf, fields, per_row: 5)
      cells = fields.map do |label, value|
        { content: "<font size='6.5'><color rgb='#{MUTED}'>#{escape(label.upcase)}</color></font>\n<b>#{escape(text(value))}</b>", inline_format: true }
      end
      rows = cells.each_slice(per_row).map { |row| row + Array.new(per_row - row.size, "") }
      pdf.table(rows, width: pdf.bounds.width, cell_style: { border_color: RULE, border_width: 0.5, padding: [ 3, 5, 5, 5 ] })
      pdf.move_down 10
    end

    def grid(pdf, header, rows, right: [], column_widths: {}, total_row: false)
      pdf.table([ header ] + rows, header: true, width: pdf.bounds.width, column_widths:,
                cell_style: { borders: [ :bottom ], border_color: RULE, border_width: 0.5, padding: [ 3, 5 ], size: 8.5 }) do |table|
        table.row(0).font_style = :bold
        table.row(0).background_color = FILL
        table.row(0).size = 7.5
        right.each { table.column(_1).filter { |cell| cell.colspan == 1 }.align = :right }
        if total_row
          table.row(-1).borders = [ :top ]
          table.row(-1).border_width = 1.2
          table.row(-1).border_color = INK
        end
      end
      pdf.move_down 12
    end

    # For Prawn's inline formatting.
    def escape(string) = string.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end
