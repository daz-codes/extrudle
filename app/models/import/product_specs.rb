# Product specs, matched by code. A new code is added; an existing code is
# changed through ProductSpec::Revision, so a spec already on an order gets
# its next revision. Line rates come from columns like "D1 rate (kg/h)".
class Import::ProductSpecs < Import::Base
  column :code, required: true, aliases: %w[ spec spec_code product_code ], example: "BF-700-250"
  column :customer, aliases: %w[ customer_name ], example: "Brightform Packaging Ltd", hint: "Blank for a stock spec."
  column :width_mm, label: "Width (mm)", aliases: %w[ width ], example: "700"
  column :thickness, label: "Thickness", aliases: %w[ micron thickness_micron gauge thickness_um ], example: ".250", hint: "Microns (250) or as on the plan (.250)."
  column :material_type, aliases: %w[ material ], example: "Clear", hint: "Clear or Laminated."
  column :pe, label: "PE", example: "No"
  column :silicone, example: "Underside", hint: "None, Underside, Reverse or Both."
  column :silicone_pct, label: "Silicone %", aliases: %w[ silicone_percent silicone_pct ], example: "0.5"
  column :antiblock, example: "Yes"
  column :antifog_pct, label: "Anti-fog %", aliases: %w[ antifog anti_fog anti_fog_pct antifog_percent ], example: "", hint: "Blank for none."
  column :core_inches, label: "Core (inches)", aliases: %w[ core core_size ], example: "6"
  column :core_orientation, aliases: %w[ orientation ], example: "Horizontal"
  column :reel_limit, example: "Max diameter", hint: "Max diameter or Max roll on side."
  column :max_diameter_mm, label: "Max diameter (mm)", aliases: %w[ max_diameter ], example: "1000"
  column :max_reel_kg, label: "Max reel (kg)", aliases: %w[ max_reel_weight max_reel ], example: "1100"
  column :pallet_type, aliases: %w[ pallet ], example: "Euro", hint: "Euro or Standard."
  column :reels_per_pallet, example: "2"
  column :label_inside_core, example: "No"
  column :packaging_notes, aliases: %w[ packaging additional_info ], example: "Best-quality pallets"
  column :customer_part_no, aliases: %w[ part_no part_number ], example: "BF-2231"
  column :customer_tool_no, aliases: %w[ tool_no tool_number ]
  column :customer_product_code, aliases: %w[ customer_code ]
  column :customer_description, aliases: %w[ description ]

  def self.description = "Matched by code. A spec already on an order gets a new revision. Add a rate column per line, e.g. \"D1 rate (kg/h)\"."

  def self.template_headers = super + Line.active.ordered.map { "#{_1.name} rate (kg/h)" }
  def self.template_example = super + Line.active.ordered.map { "190" }

  private
    # "D1 rate (kg/h)", "rate_d1", "d1_kg_h" → "rate:D1"
    def extra_column(key)
      name = key[/\A(.+?)_rate(?:_kg_h)?\z/, 1] || key[/\Arate_(.+?)(?:_kg_h)?\z/, 1] || key[/\A(.+?)_kg_h\z/, 1]
      line = name && Line.where("LOWER(name) = ?", name.tr("_", " ")).first
      line && "rate:#{line.name}"
    end

    def import_row(values)
      code = require_value(values, "code", "Code").upcase
      spec = ProductSpec.where(code:).order(:revision).last
      attributes = spec_attributes(values)

      if spec.nil?
        spec = ProductSpec.new(code:, **attributes)
        spec.save!
        action = :created
      else
        revision = ProductSpec::Revision.new(spec, attributes)
        raise ActiveRecord::RecordInvalid, spec unless revision.save

        action = revision.revised? ? :revised : (spec.previous_changes.except("updated_at").any? ? :updated : :unchanged)
        spec = revision.spec
      end
      action = :updated if save_rates(spec, values) && action == :unchanged
      [ "#{code} rev #{spec.revision}", action ]
    end

    def spec_attributes(values)
      attributes = values.slice("width_mm", "max_diameter_mm", "reels_per_pallet", "packaging_notes", "customer_part_no",
                                "customer_tool_no", "customer_product_code", "customer_description", "silicone_pct", "antifog_pct", "max_reel_kg", "core_inches")
      attributes["customer"] = find_by_name(Customer, values["customer"], "customer") if values["customer"]
      attributes["thickness_micron"] = thickness(values["thickness"]) if values["thickness"]
      attributes["material_type"] = choice(values["material_type"], ProductSpec.material_types.keys, "Material type") if values["material_type"]
      attributes["silicone"] = choice(values["silicone"], ProductSpec.silicones.keys, "Silicone") if values["silicone"]
      attributes["core_orientation"] = choice(values["core_orientation"], ProductSpec.core_orientations.keys, "Core orientation") if values["core_orientation"]
      attributes["reel_limit"] = choice(values["reel_limit"], ProductSpec.reel_limits.keys, "Reel limit") if values["reel_limit"]
      attributes["pallet_type"] = choice(values["pallet_type"], ProductSpec.pallet_types.keys, "Pallet type") if values["pallet_type"]
      %w[ pe antiblock label_inside_core ].each do |flag|
        attributes[flag] = boolean(values[flag], flag.humanize) if values.key?(flag)
      end
      attributes
    end

    def thickness(value)
      RunCheck.parse_reading("thickness", value)
    rescue ArgumentError => e
      raise RowError, "Thickness #{e.message}"
    end

    # Returns true if any rate changed.
    def save_rates(spec, values)
      values.select { |key, _| key.start_with?("rate:") }.map do |key, value|
        line = Line.find_by!(name: key.delete_prefix("rate:"))
        rate = spec.line_rates.find_or_initialize_by(line:)
        rate.kg_per_hour = Integer(value.delete(","), exception: false) || raise(RowError, "#{line.name} rate must be a whole number of kg/h, not \"#{value}\"")
        changed = rate.changed?
        rate.save!
        changed
      end.any?
    end
end
