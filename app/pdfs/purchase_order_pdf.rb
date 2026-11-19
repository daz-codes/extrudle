# The purchase order we email to a supplier. A4 portrait.
#
# Uses Prawn's built-in Helvetica (Windows-1252), so it needs no font files.
# Characters outside that set (e.g. "ł") are transliterated rather than raising.
class PurchaseOrderPdf
  include PdfFormatting

  FOOTER_HEIGHT = 20

  def initialize(order)
    @order = order
  end

  def render
    # The bottom margin leaves room for the footer, drawn below the content area.
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 40 + FOOTER_HEIGHT, 40 ], info: { Title: title, Creator: "Extrudle" })
    pdf.font "Helvetica"
    pdf.font_size 10
    pdf.fill_color INK

    header(pdf)
    parties(pdf)
    terms(pdf)
    lines(pdf)
    notes(pdf)
    footer(pdf)
    pdf.render
  end

  private
    attr_reader :order

    def title
      "Purchase order #{order.number}#{" (draft)" if order.draft?}"
    end

    def header(pdf)
      top = pdf.cursor
      pdf.bounding_box([ 0, top ], width: pdf.bounds.width / 2) do
        pdf.text text(Company.name), size: 16, style: :bold
        (Company.address + Company.contact_lines).each { |line| pdf.text text(line), color: MUTED }
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([ pdf.bounds.width / 2, top ], width: pdf.bounds.width / 2) do
        pdf.text(order.draft? ? "DRAFT PURCHASE ORDER" : "PURCHASE ORDER", size: 16, style: :bold, align: :right)
        pdf.text order.number, size: 14, align: :right
        pdf.move_down 4
        pdf.text "Date: #{date(order.order_date)}", align: :right
        pdf.text("Not yet sent: do not supply against this copy.", align: :right, color: BAD, style: :bold) if order.draft?
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
      pdf.move_down 16
    end

    def parties(pdf)
      supplier = order.supplier
      supplier_lines = [ supplier.name, supplier.contact_name.presence && "Attn: #{supplier.contact_name}",
                         supplier.country, supplier.email, supplier.phone ].compact_blank

      boxes(pdf, [ [ "Supplier", supplier_lines ], [ "Deliver to", [ Company.name ] + Company.delivery_address ] ])
    end

    def terms(pdf)
      rows = [ [ "Currency", order.currency ], [ "Incoterm", order.incoterm || "—" ],
               [ "Expected delivery", date(order.expected_on) ], [ "Your ref", order.supplier_ref || "—" ] ]
      pdf.table([ rows.map(&:first), rows.map { text(_1.last) } ], width: pdf.bounds.width,
                cell_style: { borders: [], padding: [ 2, 6 ] }) do |table|
        table.row(0).text_color = MUTED
        table.row(0).size = 8
        table.row(1).font_style = :bold
      end
      pdf.move_down 16
    end

    def lines(pdf)
      header = [ "Material", "Grade", "Quantity", "Price / t (#{order.currency})", "Total (#{order.currency})" ]
      body = order.lines.map do |line|
        [ text(line.material.name), text(line.material.grade.to_s), quantity(line.quantity_g, line.quantity_unit),
          money(line.price_per_tonne_cents), money(line.total_cents) ]
      end
      total = [ { content: "Total", colspan: 2, font_style: :bold }, quantity(order.total_g),
                "", { content: money(order.total_cents), font_style: :bold } ]

      pdf.table([ header ] + body + [ total ], header: true, width: pdf.bounds.width,
                column_widths: { 2 => 80, 3 => 95, 4 => 95 },
                cell_style: { borders: [ :bottom ], border_color: RULE, padding: [ 6, 6 ] }) do |table|
        table.row(0).font_style = :bold
        table.row(0).background_color = FILL
        table.row(0).size = 9
        table.columns(2..4).align = :right
        table.row(-1).borders = [ :top ]
        table.row(-1).border_width = 1.5
        table.row(-1).border_color = INK
      end
      pdf.move_down 16
    end

    def notes(pdf)
      return if order.notes.blank?

      pdf.text "Notes", style: :bold
      pdf.text text(order.notes)
      pdf.move_down 12
    end

    def footer(pdf)
      pdf.text text(Company.po_terms.to_s), size: 8, color: MUTED if Company.po_terms.present?
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

    def money(cents)
      "#{Money.symbol(order.currency)}#{number_with_delimiter(DecimalInput.from_scaled_integer(cents, 100, pad: true))}"
    end
end
