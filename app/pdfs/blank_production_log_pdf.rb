# A blank form 5.4.1.2 to fill in by hand if Extrudle is down (PLAN.md Slice 9).
# The same layout as ProductionLogPdf, with boxes and ruled rows to write in:
# page 1 the job, checks and materials, page 2 the reel sheet and close-out.
# What's written on it is typed into Extrudle afterwards.
# Working assumption, see PLAN.md §11 Q72.
class BlankProductionLogPdf
  include PdfFormatting
  include LogLayout

  FOOTER_HEIGHT = 20
  REEL_ROWS = 22 # a 10 t job is about 10 reels; keeps the close-out on page 2
  MATERIAL_ROWS = 8
  BOX = 28 # height of a box to write in

  def initialize(line: nil)
    @line = line
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 36, 36, 36 + FOOTER_HEIGHT, 36 ], info: { Title: "Blank production log", Creator: "Extrudle" })
    pdf.font "Helvetica"
    pdf.font_size 9
    pdf.fill_color INK

    header(pdf)
    field_grid(pdf, [ "Customer", "Order", "Spec", "Micron", "Width", "Material", "PE", "Silicone", "Antiblock", "Core",
                      "Reel size", "Quantity", "Required by", "Started", "Ended" ].index_with(""), height: BOX)
    field_grid(pdf, [ "Antiblock batch", "Silicone batch", "PE film batch", "Technician (days)", "Technician (nights)" ].index_with(""), height: BOX)
    section(pdf, "Special instructions")
    field_grid(pdf, { "" => "" }, per_row: 1, height: BOX * 1.5)
    yes_no(pdf, "prestart", "Prestart checks")
    readings(pdf, "Width and thickness at start-up")
    section(pdf, "Materials loaded")
    grid(pdf, [ "Feed", "Material", "Supplier batch", "Bag", "Lot", "Reels from–to", "Initials" ],
         Array.new(MATERIAL_ROWS) { Array.new(7, "") }, row_height: 18)

    pdf.start_new_page
    section(pdf, "Reels")
    grid(pdf, [ "Reel", "Time", "Weight (kg)", "Length (m)", "Pallet", "Initials", "Running total (kg)" ],
         Array.new(REEL_ROWS) { |index| [ (index + 1).to_s, *Array.new(6, "") ] }, row_height: 15.5)
    readings(pdf, "Width and thickness at the end of the run")
    yes_no(pdf, "line_clearance", "Line clearance")
    section(pdf, "Comments and corrective actions")
    field_grid(pdf, { "" => "" }, per_row: 1, height: BOX * 1.6)
    section(pdf, "Sign-off")
    field_grid(pdf, { "Started by" => "", "Finished by" => "", "No. of deliveries" => "" }, per_row: 3, height: BOX)
    signature_lines(pdf)
    footer(pdf)
    pdf.render
  end

  def filename = "blank-production-log#{"-#{@line.name.downcase}" if @line}.pdf"

  private
    def header(pdf)
      top = pdf.cursor
      pdf.bounding_box([ 0, top ], width: pdf.bounds.width - 150) do
        pdf.text text(Company.name), size: 9, color: MUTED
        pdf.text "PRODUCTION LOG", size: 18, style: :bold
        pdf.text "#{LogLayout::FORM} · Line #{@line ? text(@line.name) : "______"}", color: MUTED
      end
      left_bottom = pdf.cursor
      pdf.bounding_box([ pdf.bounds.width - 140, top ], width: 140, height: 52) do
        pdf.stroke_color INK
        pdf.line_width 1.5
        pdf.stroke_bounds
        pdf.move_down 6
        pdf.text "DESPATCH No.", size: 7, style: :bold, color: MUTED, align: :center
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
      pdf.move_down 8
      pdf.text "Paper copy for when Extrudle is down. Type it into Extrudle once it's back.", size: 8, color: MUTED
      pdf.move_down 6
    end

    def yes_no(pdf, stage, heading)
      section(pdf, heading)
      rows = ProductionRun::Checklist.items(stage).values.map { |label| [ label, "Yes  /  No", "", "" ] }
      grid(pdf, [ "Check", "Answer (circle)", "Initials", "Time" ], rows, column_widths: { 0 => 230, 1 => 90 }, row_height: 18)
    end

    def readings(pdf, heading)
      section(pdf, heading)
      rows = ProductionRun::Checklist::MEASUREMENTS.values.map { |info| [ "#{info[:label]} (#{info[:unit]})", "", "", "", "", "" ] }
      grid(pdf, [ "Reading", "Target", "Actual", "In tolerance (Y/N)", "Initials", "Time" ], rows, row_height: 18)
    end

    def signature_lines(pdf)
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
      pdf.repeat(:all) do
        pdf.bounding_box([ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width * 0.8, height: 12) do
          pdf.text text("#{LogLayout::FORM} · paper fallback · type into Extrudle when it's back"), size: 7, color: MUTED
        end
      end
      pdf.number_pages "Page <page> of <total>", at: [ 0, -FOOTER_HEIGHT + 10 ], width: pdf.bounds.width, align: :right, size: 7, color: MUTED
    end
end
