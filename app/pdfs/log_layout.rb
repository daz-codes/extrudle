# The building blocks of the form 5.4.1.2 layout, shared by a filled-in log
# (ProductionLogPdf) and the blank paper fallback (BlankProductionLogPdf).
module LogLayout
  include PdfFormatting

  FORM = "Form 5.4.1.2"

  private
    # Small-caps heading with a rule, kept with at least the next few lines.
    def section(pdf, heading)
      pdf.start_new_page if pdf.cursor < 80
      pdf.move_down 4
      pdf.text heading.upcase, size: 8, style: :bold, color: MUTED
      pdf.move_down 3
    end

    # Label-over-value boxes, five to a row, like the boxes at the top of the paper form.
    # height: room to write in, for the blank form.
    def field_grid(pdf, fields, per_row: 5, height: nil)
      cells = fields.map do |label, value|
        { content: "<font size='6.5'><color rgb='#{MUTED}'>#{escape(label.upcase)}</color></font>\n<b>#{escape(text(value))}</b>", inline_format: true }
      end
      rows = cells.each_slice(per_row).map { |row| row + Array.new(per_row - row.size, "") }
      style = { border_color: RULE, border_width: 0.5, padding: [ 3, 5, 5, 5 ] }
      style[:height] = height if height
      pdf.table(rows, width: pdf.bounds.width, cell_style: style)
      pdf.move_down 10
    end

    # row_height: room to write in, for the blank form.
    def grid(pdf, header, rows, right: [], column_widths: {}, total_row: false, row_height: nil)
      style = { borders: [ :bottom ], border_color: RULE, border_width: 0.5, padding: [ 3, 5 ], size: 8.5 }
      style[:height] = row_height if row_height
      pdf.table([ header ] + rows, header: true, width: pdf.bounds.width, column_widths:, cell_style: style) do |table|
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
