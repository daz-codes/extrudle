require "test_helper"

class ImportTest < ActiveSupport::TestCase
  def import(kind, text)
    Import.for(kind, text).tap(&:save)
  end

  test "customers: matched by name in any case, loose headers, blanks leave things alone" do
    customers(:brightform).update!(phone: "0113 000")
    text = "Customer Name,Sage Account Ref,VAT code,Phone\r\nBRIGHTFORM PACKAGING LTD,bright01,t1,\r\nNew Trays Ltd,newtra01,T4,01632 960111\r\n"
    result = import("customers", text)

    assert result.ok?, result.results.flat_map(&:errors).to_sentence
    assert_equal [ :updated, :created ], result.results.map(&:action)
    brightform = customers(:brightform).reload
    assert_equal [ "BRIGHT01", "T1", "0113 000" ], [ brightform.sage_account_ref, brightform.sage_tax_code, brightform.phone ]
    assert_equal "T4", Customer.find_by!(name: "New Trays Ltd").sage_tax_code
  end

  test "all or nothing: one bad row and nothing is saved, with the line and reason" do
    text = "name,currency\nGood Customer,GBP\nBad Customer,XYZ\n"
    result = import("customers", text)
    assert_not result.ok?
    assert_not Customer.exists?(name: "Good Customer")
    bad = result.results.last
    assert_equal [ 3, "Bad Customer", :failed ], [ bad.line, bad.label, bad.action ]
    assert_match(/Currency/, bad.errors.to_sentence)
  end

  test "preview checks every row but saves nothing" do
    preview = Import.for("customers", "name\nPreview Ltd\n")
    assert preview.preview
    assert_equal [ :created ], preview.results.map(&:action)
    assert_not Customer.exists?(name: "Preview Ltd")
  end

  test "missing required columns and unknown columns are reported" do
    result = Import.for("materials", "name,colour\nJADE,blue\n")
    assert_not result.preview
    assert_equal [ "The \"Category\" column is missing" ], result.problems
    assert_equal [ "Column \"colour\" isn't used and will be ignored" ], result.warnings
    assert_equal [ "The file is empty" ], Import.for("materials", "").problems
    assert_equal [ "There are no rows under the header" ], Import.for("materials", "name,category\n").problems
  end

  test "suppliers and materials, with categories and suppliers found by name" do
    assert import("suppliers", "Name,Country,Currency,Incoterm\nNordic Resin AB,Sweden,eur,fob\n").ok?
    supplier = Supplier.find_by!(name: "Nordic Resin AB")
    assert_equal [ "EUR", "FOB" ], [ supplier.currency, supplier.incoterm ]

    result = import("materials", "Name,Category,Supplier,Origin,Source\nNordic Clear,Virgin polymer,nordic resin ab,Virgin,Purchased\nMystery,Nope,,,\n")
    assert_not result.ok?
    assert_equal [ "There's no material category called \"Nope\"" ], result.results.last.errors

    assert import("materials", "Name,Category,Supplier\nNordic Clear,Virgin polymer,Nordic Resin AB\n").ok?
    assert_equal supplier, Material.find_by!(name: "Nordic Clear").supplier
  end

  test "product specs: new codes with line rates, paper gauge thickness, yes/no flags" do
    text = "Code,Customer,Width (mm),Thickness,Silicone,Silicone %,PE,Antiblock,Reel limit,Max diameter (mm),Max reel (kg),D1 rate (kg/h),rate_d2\n" \
           "imp-700-250,Brightform Packaging Ltd,700,.250,Underside,0.5,No,Yes,Max diameter,1000,\"1,100\",190,175\n"
    result = import("product_specs", text)
    assert result.ok?, result.results.flat_map(&:errors).to_sentence

    spec = ProductSpec.find_by!(code: "IMP-700-250")
    assert_equal [ 700, 250, "underside", 50, false, true, 1_100_000 ],
                 [ spec.width_mm, spec.thickness_micron, spec.silicone, spec.silicone_bp, spec.pe, spec.antiblock, spec.max_reel_g ]
    assert_equal({ "D1" => 190, "D2" => 175 }, spec.line_rates.includes(:line).to_h { [ _1.line.name, _1.kg_per_hour ] })
  end

  test "product specs: a spec already on an order gets a new revision" do
    spec = product_specs(:bf_700)
    result = import("product_specs", "Code,Packaging notes\n#{spec.code},Corner boards on every pallet\n")
    assert result.ok?, result.results.flat_map(&:errors).to_sentence
    assert_equal :revised, result.results.sole.action
    latest = ProductSpec.where(code: spec.code).order(:revision).last
    assert_equal [ spec.revision + 1, "Corner boards on every pallet" ], [ latest.revision, latest.packaging_notes ]
    assert_not_equal "Corner boards on every pallet", spec.reload.packaging_notes, "the old revision is untouched"
  end

  test "product specs: bad values name the column" do
    result = import("product_specs", "Code,Width (mm),Thickness,Silicone,PE\nBAD-1,700,thick,Sideways,maybe\n")
    assert_not result.ok?
    assert_match "Thickness is not a number", result.results.sole.errors.to_sentence
  end

  test "opening stock: each row is received as lots, split across its bags" do
    text = "Material,Total kg,Bags,Supplier batch,First bag no,Location,Received\nJADE,\"2,200\",2,CZ-1,101,Storage,01/11/2026\n"
    result = import("opening_stock", text)
    assert result.ok?, result.results.flat_map(&:errors).to_sentence

    lots = Lot.where(supplier_lot_ref: "CZ-1").order(:code)
    assert_equal [ "101", "102" ], lots.map(&:bag_no)
    assert_equal [ 1_100_000, 1_100_000 ], lots.map(&:quantity_g)
    assert lots.all?(&:storage?)
    assert_equal Date.new(2026, 11, 1), lots.first.received_on
  end

  test "templates have every column and an example that checks out" do
    Import::KINDS.each_key do |kind|
      klass = Import.kind_class(kind)
      header = Import::CsvReader.parse(klass.template_csv).first
      assert_equal klass.template_headers, header
    end
    assert Import.for("suppliers", Import::Suppliers.template_csv).preview
    assert Import.for("customers", Import::Customers.template_csv).preview
  end
end
