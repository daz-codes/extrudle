# The bag variance report (PLAN.md §4): for each bag marked empty, what it
# weighed in, what production runs were allocated, and the difference posted
# when it was reconciled. Also lists bags on the lines now and empty bags
# waiting for a log to finish.
class Stock::Variance
  # Working assumption, see PLAN.md §11 Q50: flag a bag that's more than 5% out.
  FLAG_BP = 500

  Row = Data.define(:lot, :in_g, :used_g, :variance_g) do
    # Signed, as a share of what went in, in basis points.
    def variance_bp = in_g.zero? ? 0 : variance_g * 10_000 / in_g
    def flagged? = variance_bp.abs > FLAG_BP
  end

  def initialize(since: 90.days.ago)
    @since = since
  end

  def reconciled
    @reconciled ||= lots.where.not(reconciled_at: nil).where(reconciled_at: @since..).order(reconciled_at: :desc).map do |lot|
      movements = lot.movements.to_a
      variance = movements.find { _1.adjustment? && _1.note == Stock::Reconciliation::NOTE }&.quantity_g.to_i
      used = -movements.select(&:issue_to_production?).sum(&:quantity_g)
      Row.new(lot:, in_g: movements.sum(&:quantity_g) + used - variance, used_g: used, variance_g: variance)
    end
  end

  def waiting
    @waiting ||= lots.where.not(emptied_at: nil).where(reconciled_at: nil).order(:emptied_at).to_a
  end

  # [ [ run, load ] ] for the bags feeding running logs now.
  def on_lines
    @on_lines ||= ProductionRun.running.includes(:line, material_loads: { lot: :material }).sort_by { _1.line.name }.flat_map do |run|
      run.current_loads.values.reject { _1.lot.emptied? }.map { [ run, _1 ] }
    end
  end

  def total_in_g = reconciled.sum(&:in_g)
  def total_variance_g = reconciled.sum(&:variance_g)

  private
    def lots
      Lot.includes(:material, :movements, material_loads: :production_run)
    end
end
