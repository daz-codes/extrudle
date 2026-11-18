module ApplicationHelper
  # Candidate designs for the preview switcher (see shared/_theme_switcher).
  THEMES = { "highlighter" => "Highlighter", "swoosh" => "Swoosh", "lime" => "Lime" }.freeze

  def current_theme
    THEMES.key?(cookies[:theme]) ? cookies[:theme] : THEMES.keys.first
  end

  # 1_250_500 g => "1,250.5 kg"
  def kg(grams, precision: 1)
    return "—" if grams.nil?
    "#{number_with_precision(Weight.to_kg(grams), precision: precision, delimiter: ',', strip_insignificant_zeros: true)} kg"
  end

  # 12_500_000 g => "12.50 t"
  def tonnes(grams, precision: 2)
    return "—" if grams.nil?
    "#{number_with_precision(Weight.to_tonnes(grams), precision: precision, delimiter: ',')} t"
  end

  # money(123_456, "GBP") => "£1,234.56"
  def money(cents, currency)
    return "—" if cents.nil?
    number_to_currency(Money.to_major(cents), unit: Money.symbol(currency), precision: 2)
  end

  def nav_link(label, path, active: current_page?(path))
    link_to label, path, class: "nav-link", aria: { current: (active ? "page" : nil) }
  end
end
