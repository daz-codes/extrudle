module MaterialLoadsHelper
  # "1–5", "5 onwards", or "none" when the next bag went on first.
  def reel_range_text(range)
    return "none" if range.nil?
    return "#{range.begin} onwards" if range.end.nil?

    range.begin == range.end ? range.begin.to_s : "#{range.begin}–#{range.end}"
  end

  # The supplier's batch and bag number, as written on the paper log ("bag 939").
  def bag_reference(lot)
    [ lot.supplier_lot_ref, ("bag #{lot.bag_no}" if lot.bag_no) ].compact.join(" · ").presence
  end

  def recipe_percent(share_bp)
    "#{DecimalInput.from_scaled_integer(share_bp, 100)}%"
  end

  # Bags that can go on a feed, for the lot code box's suggestions.
  def loadable_lots
    Lot.in_stock.where(location: ProductionRun::LoadMaterial::LOADABLE_LOCATIONS, emptied_at: nil).includes(:material).by_code
  end
end
