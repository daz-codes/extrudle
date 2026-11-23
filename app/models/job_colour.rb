# Colours for job bars on the planner timeline. A customer has a default
# colour and each job (schedule block) can override it. With neither, jobs
# keep the Lemon and Lime look: lime, or lemon for urgent orders.
# The swatches themselves live in app/assets/tailwind/application.css
# (.job-colour-<name>); views never use raw hex.
module JobColour
  NAMES = %w[ lime lemon banana mango mandarin cherry raspberry blackcurrant blueberry pistachio chocolate ].freeze

  # Bars dark enough to need white text.
  DARK = %w[ cherry raspberry blackcurrant blueberry chocolate ].freeze

  def self.for(block)
    block.colour.presence || block.sales_order&.customer&.colour.presence ||
      (block.sales_order&.urgent? ? "lemon" : "lime")
  end

  def self.css_class(name) = "job-colour-#{name}"

  def self.label(name) = name.to_s.humanize
end
