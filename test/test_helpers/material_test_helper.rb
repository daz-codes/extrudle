module MaterialTestHelper
  # A bag of a material, received today: bag(materials(:jade), kg: 1_000).
  def bag(material, kg: 1_000, location: "on_site", bag_no: nil)
    receipt = Stock::Receipt.new(material_id: material.id, quantity: kg.to_s, bags: 1, location:, first_bag_no: bag_no)
    receipt.save!
    receipt.lots.sole
  end

  def capping_polymer
    category = MaterialCategory.find_or_create_by!(name: "Capping polymer") { _1.position = 3 }
    Material.find_or_create_by!(name: "EuroCap Co-Ex") { _1.material_category = category }
  end

  def pcw_flake
    Material.find_or_create_by!(name: "Clear PCW flake") { _1.assign_attributes(material_category: material_categories(:recycled), origin: "recycled") }
  end

  def start_run(order_line = sales_order_lines(:bf_open_700), line: lines(:d1))
    start = ProductionRun::Start.new(schedule_block: planned_job(order_line, line:))
    assert start.save, start.errors.full_messages.to_sentence
    start.run
  end

  def load_bag(run, lot, feed: nil, from_reel_no: nil, previous_empty: true)
    loading = ProductionRun::LoadMaterial.new(run:, lot_code: lot.code, feed:, from_reel_no:, previous_empty:)
    assert loading.save, loading.errors.full_messages.to_sentence
    run.material_loads.reset
    loading.load
  end

  def add_reels(run, *kgs)
    kgs.each { run.reels.create!(weight_kg: _1.to_s) }
    run.reels.reset
  end

  def finish_cleanly(run)
    run.record_measurement(stage: "end_of_run", item: "width", actual: run.product_spec.width_mm.to_s)
    run.record_measurement(stage: "end_of_run", item: "thickness", actual: run.product_spec.thickness_micron.to_s)
    ProductionRun::Checklist.items("line_clearance").each_key { run.record_check(stage: "line_clearance", item: _1, passed: true) }
    run.reload.finish!
  end
end

module DispatchTestHelper
  # A production log for an order line with reels on pallets:
  #   run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ])  # pallet 1: two reels, pallet 2: one
  def run_with_pallets(order_line = sales_order_lines(:bf_open_700), line: lines(:d1), pallets: [ [ 500, 500 ], [ 400 ] ], finish: false)
    start = ProductionRun::Start.new(schedule_block: planned_job(order_line, line:))
    assert start.save, start.errors.full_messages.to_sentence
    run = start.run
    pallets.each.with_index(1) do |kgs, pallet_no|
      kgs.each { run.reels.create!(weight_kg: _1.to_s, pallet_no:) }
    end
    run.reels.reset
    if finish
      run.update_columns(status: "finished", ended_at: Time.current)
    end
    run
  end

  def delivery_note_for(run, pallet_nos, dispatch: false)
    note = run.sales_order.delivery_notes.build
    assert note.save_with_number
    note.set_pallets!(pallet_nos.map { [ run.id, _1 ] })
    note.mark_dispatched! if dispatch
    note
  end
end
