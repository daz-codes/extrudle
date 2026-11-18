module MasterDataHelper
  MASTER_DATA_SECTIONS = [
    [ "Specs", :product_specs ],
    [ "Customers", :customers ],
    [ "Suppliers", :suppliers ],
    [ "Materials", :materials ],
    [ "Categories", :material_categories ],
    [ "Lines", :lines ]
  ].freeze

  def master_data_page?
    controller_name == "master_data" || MASTER_DATA_SECTIONS.any? { |_, name| name.to_s == controller_name } || controller_name == "line_rates"
  end

  def micron(value)
    value ? "#{number_with_delimiter(value)} µm" : "—"
  end

  def mm(value)
    value ? "#{number_with_delimiter(value)} mm" : "—"
  end

  def yes_no(value)
    value ? "Yes" : "No"
  end

  def status_badge(record)
    if record.active?
      tag.span("Active", class: "badge bg-ok-50 text-ok-700")
    else
      tag.span("Inactive", class: "badge bg-ink-100 text-ink-600")
    end
  end

  def silicone_summary(spec)
    return "None" if spec.silicone_none?
    "#{spec.silicone.humanize} #{spec.silicone_pct}%"
  end

  def reel_size_summary(spec)
    limit = spec.max_roll_on_side? ? "Max roll on side" : "Max #{mm(spec.max_diameter_mm)} dia."
    [ limit, (kg(spec.max_reel_g) if spec.max_reel_g) ].compact.join(" · ")
  end
end
