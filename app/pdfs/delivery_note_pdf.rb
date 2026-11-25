# The delivery note that goes with the lorry. A4 portrait.
# Laid out from the fields we hold until Stu sends a sample (PLAN.md §11 Q4):
# our details, the customer and delivery address, the order and their PO,
# one row per pallet, totals, and a box for the customer to sign.
class DeliveryNotePdf
  include PdfFormatting

  FOOTER_HEIGHT = 20

  def initialize(note)
    @note = note
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 40 + FOOTER_HEIGHT, 40 ], info: { Title: title, Creator: "Extrudle" })
    pdf.font "Helvetica"
    pdf.font_size 10
    pdf.fill_color INK

    header(pdf)
    parties(pdf)
    references(pdf)
    pallets(pdf)
    notes(pdf)
    received(pdf)
    footer(pdf)
    pdf.render
  end

  private
    attr_reader :note

    def order = note.sales_order

    def title = "Delivery note #{note.number}#{" (draft)" if note.draft?}"

    def header(pdf)
      top = pdf.cursor
      pdf.bounding_box([ 0, top ], width: pdf.bounds.width / 2) do
        pdf.text text(Company.name), size: 16, style: :bold
        (Company.address + Company.contact_lines).each { |line| pdf.text text(line), color: MUTED }
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([ pdf.bounds.width / 2, top ], width: pdf.bounds.width / 2) do
        pdf.text "DELIVERY NOTE", size: 16, style: :bold, align: :right
        pdf.text note.number, size: 14, align: :right
        pdf.move_down 4
        pdf.text "Date: #{date(note.dispatched_on || Date.current)}", align: :right
        pdf.text("DRAFT: not yet dispatched", align: :right, color: BAD, style: :bold) if note.draft?
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
      pdf.move_down 16
    end

    def parties(pdf)
      customer = order.customer
      address = (note.delivery_address || customer.address).to_s.lines.map(&:strip).compact_blank
      boxes(pdf, [ [ "Customer", [ customer.name, customer.contact_name, customer.phone ].compact_blank ],
                   [ "Deliver to", [ customer.name, order.delivery_site ].compact + address ] ])
    end

    def references(pdf)
      batches = order.lines.filter_map(&:customer_batch_no).uniq
      rows = [ [ "Our order", order.number ], [ "Your order", order.customer_po_ref || "—" ],
               [ "Haulier", note.haulier || "—" ], [ "Vehicle", note.vehicle_reg || "—" ] ]
      rows << [ "Your batch", batches.join(", ") ] if batches.any?
      pdf.table([ rows.map(&:first), rows.map { text(_1.last) } ], width: pdf.bounds.width,
                cell_style: { borders: [], padding: [ 2, 6 ] }) do |table|
        table.row(0).text_color = MUTED
        table.row(0).size = 8
        table.row(1).font_style = :bold
      end
      pdf.move_down 16
    end

    def pallets(pdf)
      header = [ "Pallet", "Product", "Reels", "Reel nos.", "Net weight (kg)" ]
      body = note.lines.flat_map do |line|
        line.pallets.map do |pallet|
          [ pallet.label, text(description(line.order_line.product_spec)), pallet.reel_count.to_s,
            helpers.reel_numbers_text(pallet.reel_numbers), kg_number(pallet.weight_g) ]
        end
      end
      pallet_count = note.lines.sum { _1.pallets.size }
      total = [ { content: "#{pallet_count} #{"pallet".pluralize(pallet_count)}", colspan: 2, font_style: :bold },
                { content: note.lines.sum(&:reel_count).to_s, font_style: :bold }, "",
                { content: kg_number(note.total_g), font_style: :bold } ]

      pdf.table([ header ] + body + [ total ], header: true, width: pdf.bounds.width, column_widths: { 0 => 60, 2 => 45, 4 => 90 },
                cell_style: { borders: [ :bottom ], border_color: RULE, padding: [ 6, 6 ] }) do |table|
        table.row(0).font_style = :bold
        table.row(0).background_color = FILL
        table.row(0).size = 9
        table.columns(2).align = :right
        table.columns(4).align = :right
        table.row(-1).borders = [ :top ]
        table.row(-1).border_width = 1.5
        table.row(-1).border_color = INK
      end
      pdf.move_down 16
    end

    # Spec, size and the customer's own codes, as they'd recognise it.
    def description(spec)
      parts = [ spec.customer_description.presence || spec.code, "#{spec.paper_gauge} x #{spec.width_mm} mm" ]
      parts << "Part #{spec.customer_part_no}" if spec.customer_part_no.present?
      parts << "Code #{spec.customer_product_code}" if spec.customer_product_code.present?
      parts.join("\n")
    end

    def notes(pdf)
      return if note.notes.blank?

      pdf.text "Notes", style: :bold
      pdf.text text(note.notes)
      pdf.move_down 12
    end

    def received(pdf)
      pdf.start_new_page if pdf.cursor < 110
      pdf.move_down 8
      pdf.text "RECEIVED IN GOOD CONDITION", size: 8, style: :bold, color: MUTED
      pdf.move_down 24
      width = (pdf.bounds.width - 32) / 3
      %w[ Name Signature Date ].each_with_index do |label, index|
        x = index * (width + 16)
        pdf.stroke_color INK
        pdf.line_width 0.5
        pdf.stroke_horizontal_line x, x + width, at: pdf.cursor
        pdf.draw_text label, at: [ x, pdf.cursor - 10 ], size: 8
      end
      pdf.move_down 20
    end

    def footer(pdf)
      pdf.repeat(:all) do
        pdf.bounding_box([ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width * 0.8, height: 12) do
          pdf.text text(([ Company.name ] + Company.registration_lines).join("  ·  ")), size: 7, color: MUTED
        end
      end
      pdf.number_pages "Page <page> of <total>", at: [ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width, align: :right, size: 7, color: MUTED
    end

    def boxes(pdf, sections)
      width = (pdf.bounds.width - 16) / sections.size
      top = pdf.cursor
      bottoms = sections.each_with_index.map do |(heading, lines), index|
        pdf.bounding_box([ index * (width + 16), top ], width:) do
          pdf.text heading.upcase, size: 8, color: MUTED, style: :bold
          pdf.move_down 2
          lines.each { |line| pdf.text text(line) }
        end
        pdf.cursor
      end
      pdf.move_cursor_to bottoms.min
      pdf.move_down 16
    end

    def helpers = ApplicationController.helpers
end
