# Colours for job bars on the planner timeline. Every customer has a colour
# (lime unless chosen) and each job (schedule block) can override it. Lemon
# and lime are ordinary choices; urgent jobs are marked with a lemon stripe
# (PlannerHelper#urgent_stripe), not by colour.
# The swatches themselves live in app/assets/tailwind/application.css
# (.job-colour-<name>); views never use raw hex.
module JobColour
  NAMES = %w[ lime lemon banana mango mandarin cherry raspberry blackcurrant blueberry pistachio chocolate ].freeze

  DEFAULT = "lime"

  # Bars dark enough to need white text.
  DARK = %w[ cherry raspberry blackcurrant blueberry chocolate ].freeze

  def self.for(block)
    block.colour.presence || block.sales_order&.customer&.colour.presence || DEFAULT
  end

  def self.css_class(name) = "job-colour-#{name}"

  def self.label(name) = name.to_s.humanize
end
