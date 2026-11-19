# Stock on hand per material and location, computed from stock movements
# (never stored), plus what's still due on open purchase orders.
class Stock::OnHand
  Row = Data.define(:material, :by_location, :lots, :on_order_g) do
    def total_g = by_location.values.sum
    def empty? = total_g.zero? && on_order_g.zero?
  end

  Group = Data.define(:category, :rows) do
    def total_g = rows.sum(&:total_g)
    def on_order_g = rows.sum(&:on_order_g)
    def by_location(location) = rows.sum { _1.by_location.fetch(location, 0) }
  end

  def groups
    @groups ||= begin
      rows = materials.map do |material|
        Row.new(material:, by_location: totals.fetch(material.id, {}), lots: lot_counts.fetch(material.id, 0), on_order_g: on_order.fetch(material.id, 0))
      end
      rows.reject { _1.empty? && !_1.material.active? }
          .group_by { _1.material.material_category }
          .sort_by { |category, _| [ category.position, category.name ] }
          .map { |category, category_rows| Group.new(category:, rows: category_rows) }
    end
  end

  def total_g = groups.sum(&:total_g)
  def on_order_g = groups.sum(&:on_order_g)

  private
    def materials
      Material.includes(:material_category).by_name
    end

    # { material_id => { "on_site" => grams, ... } }, only lots holding stock.
    def totals
      @totals ||= StockMovement.joins(:lot).group("lots.material_id", "lots.location").sum(:quantity_g)
        .each_with_object(Hash.new { |h, k| h[k] = {} }) do |((material_id, location), grams), result|
          result[material_id][location] = grams unless grams.zero?
        end
    end

    def lot_counts
      @lot_counts ||= Lot.in_stock.group(:material_id).count
    end

    # Still due on sent or part-received POs, per material.
    def on_order
      @on_order ||= PurchaseOrderLine.joins(:purchase_order).merge(PurchaseOrder.outstanding).includes(:lots)
        .each_with_object(Hash.new(0)) { |line, result| result[line.material_id] += line.outstanding_g }
    end
end
