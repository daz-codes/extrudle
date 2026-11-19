require "test_helper"

class PurchaseOrderTest < ActiveSupport::TestCase
  test "numbers follow on from the highest PO number" do
    assert_equal "PO-00004", PurchaseOrder.next_number
    purchase_orders(:pacific_draft).update_columns(number: "PO-99999")
    assert_equal "PO-100000", PurchaseOrder.next_number
  end

  test "sales order and purchase order numbers are separate sequences" do
    assert_match(/\ASO-/, SalesOrder.next_number)
    assert_equal "PO-00004", PurchaseOrder.next_number
  end

  test "a new PO takes the supplier's currency and incoterm" do
    order = PurchaseOrder.new(supplier: suppliers(:pacific), expected_on: Date.current)
    assert order.save_with_number
    assert_equal "PO-00004", order.number
    assert_equal "USD", order.currency
    assert_equal "CIF", order.incoterm
    assert order.draft?
  end

  test "inactive suppliers can't get new POs" do
    suppliers(:pacific).update!(active: false)
    order = PurchaseOrder.new(supplier: suppliers(:pacific), expected_on: Date.current)
    assert_not order.valid?
    assert order.errors.added?(:supplier, "is inactive")
  end

  test "supplier and currency are fixed once there are lines" do
    order = purchase_orders(:pacific_draft)
    order.currency = "EUR"
    order.supplier = suppliers(:albion)
    assert_not order.valid?
    assert order.errors.of_kind?(:currency, :invalid) || order.errors.include?(:currency)
    assert order.errors.include?(:supplier)
  end

  test "total is the sum of the rounded line totals" do
    order = purchase_orders(:pacific_draft)
    order.lines.create!(material: materials(:jade), quantity: "0.333", price_per_tonne: "1000") # 33.3 p rounds down to 33
    order.lines.create!(material: materials(:jade), quantity: "0.335", price_per_tonne: "1000") # 33.5 p rounds up to 34
    assert_equal 2_728_000 + 33 + 34, order.reload.total_cents
    assert_equal 22_000_668, order.total_g
  end

  test "mark sent stamps the time and needs lines" do
    order = purchase_orders(:pacific_draft)
    freeze_time do
      order.mark_sent!
      assert order.sent?
      assert_equal Time.current, order.sent_at
      assert_equal Date.current, order.order_date
    end

    empty = PurchaseOrder.create!(number: "PO-00010", supplier: suppliers(:albion), expected_on: Date.current)
    error = assert_raises(ArgumentError) { empty.mark_sent! }
    assert_match "add at least one line", error.message
  end

  test "sent POs go back to draft to be changed, and only drafts are editable" do
    order = purchase_orders(:albion_sent)
    assert_not order.editable?
    order.back_to_draft!
    assert order.draft?
    assert order.editable?
    assert_raises(ArgumentError) { purchase_orders(:pacific_draft).back_to_draft! }
  end

  test "a PO back in draft prints today's date, not when it was first sent" do
    order = purchase_orders(:albion_sent)
    assert_equal order.sent_at.to_date, order.order_date
    order.back_to_draft!
    assert_equal Date.current, order.order_date
  end

  test "moving a PO without lines to another supplier takes that supplier's terms" do
    order = PurchaseOrder.create!(number: "PO-00010", supplier: suppliers(:albion), expected_on: Date.current)
    order.update!(supplier: suppliers(:pacific))
    assert_equal [ "USD", "CIF" ], [ order.currency, order.incoterm ]

    order.update!(supplier: suppliers(:albion), currency: "EUR")
    assert_equal [ "EUR", "DAP" ], [ order.currency, order.incoterm ], "a currency chosen in the same edit wins"
  end

  test "cancel and reopen" do
    order = purchase_orders(:albion_sent)
    order.cancel!
    assert order.cancelled?
    order.reopen!
    assert order.draft?
    assert_nil order.sent_at
    assert_raises(ArgumentError) { purchase_orders(:albion_received).cancel! }
  end

  test "overdue only while goods are still due" do
    assert purchase_orders(:albion_sent).overdue?
    assert_not purchase_orders(:albion_received).overdue?
    assert_not purchase_orders(:pacific_draft).overdue?
  end

  test "search by number, supplier ref or supplier name" do
    assert_equal [ purchase_orders(:albion_sent) ], PurchaseOrder.search("oc-11").to_a
    assert_includes PurchaseOrder.search("pacific"), purchase_orders(:pacific_draft)
    assert_equal 2, PurchaseOrder.active.count
  end

  test "close short accepts a short delivery" do
    order = purchase_orders(:albion_sent)
    Stock::Receipt.new(purchase_order_line: purchase_order_lines(:albion_jade), quantity: "900").save!
    assert order.reload.part_received?
    assert_raises(ArgumentError) { order.cancel! }

    order.close_short!
    assert order.received?
    assert order.closed_short?
    assert_raises(ArgumentError) { order.close_short! }
  end
end
