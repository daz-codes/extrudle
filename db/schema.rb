# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_100000) do
  create_table "backup_checks", force: :cascade do |t|
    t.boolean "ok", null: false
    t.text "message", null: false
    t.json "counts", default: {}, null: false
    t.integer "duration_ms"
    t.integer "requested_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requested_by_id"], name: "index_backup_checks_on_requested_by_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "contact_name"
    t.string "email"
    t.string "phone"
    t.text "address"
    t.text "notes"
    t.string "currency", default: "GBP", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sage_account_ref"
    t.string "sage_tax_code", default: "T1", null: false
    t.string "colour"
    t.index ["name"], name: "index_customers_on_name", unique: true
  end

  create_table "delivery_note_pallets", force: :cascade do |t|
    t.integer "delivery_note_id", null: false
    t.integer "production_run_id", null: false
    t.integer "pallet_no", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_note_id"], name: "index_delivery_note_pallets_on_delivery_note_id"
    t.index ["production_run_id", "pallet_no"], name: "index_delivery_note_pallets_on_production_run_id_and_pallet_no", unique: true
    t.index ["production_run_id"], name: "index_delivery_note_pallets_on_production_run_id"
    t.check_constraint "pallet_no > 0", name: "delivery_note_pallets_pallet_positive"
  end

  create_table "delivery_notes", force: :cascade do |t|
    t.string "number", null: false
    t.integer "sales_order_id", null: false
    t.string "status", default: "draft", null: false
    t.date "dispatched_on"
    t.integer "dispatched_by_id"
    t.string "haulier"
    t.string "vehicle_reg"
    t.text "delivery_address"
    t.text "notes"
    t.integer "sage_export_id"
    t.datetime "exported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dispatched_by_id"], name: "index_delivery_notes_on_dispatched_by_id"
    t.index ["number"], name: "index_delivery_notes_on_number", unique: true
    t.index ["sage_export_id"], name: "index_delivery_notes_on_sage_export_id"
    t.index ["sales_order_id"], name: "index_delivery_notes_on_sales_order_id"
    t.check_constraint "status = 'draft' OR dispatched_on IS NOT NULL", name: "delivery_notes_dispatched_on"
    t.check_constraint "status IN ('draft', 'dispatched')", name: "delivery_notes_status"
  end

  create_table "devices", force: :cascade do |t|
    t.string "name", null: false
    t.string "token_digest", null: false
    t.integer "approved_by_id"
    t.datetime "last_used_at"
    t.string "last_ip"
    t.string "user_agent"
    t.datetime "revoked_at"
    t.integer "revoked_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_devices_on_approved_by_id"
    t.index ["revoked_by_id"], name: "index_devices_on_revoked_by_id"
    t.index ["token_digest"], name: "index_devices_on_token_digest", unique: true
  end

  create_table "line_rates", force: :cascade do |t|
    t.integer "line_id", null: false
    t.integer "product_spec_id", null: false
    t.integer "kg_per_hour", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_id"], name: "index_line_rates_on_line_id"
    t.index ["product_spec_id", "line_id"], name: "index_line_rates_on_product_spec_id_and_line_id", unique: true
    t.index ["product_spec_id"], name: "index_line_rates_on_product_spec_id"
    t.check_constraint "kg_per_hour > 0", name: "line_rates_kg_per_hour_positive"
  end

  create_table "lines", force: :cascade do |t|
    t.string "name", null: false
    t.string "machine_no"
    t.integer "default_changeover_minutes", default: 60, null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "queue_starts_at"
    t.index ["name"], name: "index_lines_on_name", unique: true
    t.check_constraint "default_changeover_minutes >= 0", name: "lines_changeover_non_negative"
  end

  create_table "lots", force: :cascade do |t|
    t.string "code", null: false
    t.integer "material_id", null: false
    t.integer "purchase_order_line_id"
    t.string "supplier_lot_ref"
    t.string "bag_no"
    t.string "delivery_ref"
    t.string "location", default: "on_site", null: false
    t.date "received_on", null: false
    t.integer "initial_g", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "emptied_at"
    t.datetime "reconciled_at"
    t.index ["code"], name: "index_lots_on_code", unique: true
    t.index ["material_id", "location"], name: "index_lots_on_material_id_and_location"
    t.index ["material_id"], name: "index_lots_on_material_id"
    t.index ["purchase_order_line_id"], name: "index_lots_on_purchase_order_line_id"
    t.check_constraint "initial_g > 0", name: "lots_initial_positive"
  end

  create_table "material_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_material_categories_on_name", unique: true
  end

  create_table "material_loads", force: :cascade do |t|
    t.integer "production_run_id", null: false
    t.integer "lot_id", null: false
    t.string "feed", null: false
    t.integer "from_reel_no", null: false
    t.datetime "loaded_at", null: false
    t.boolean "carried_over", default: false, null: false
    t.boolean "marked_previous_empty", default: false, null: false
    t.string "initials"
    t.integer "user_id"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lot_id"], name: "index_material_loads_on_lot_id"
    t.index ["production_run_id", "feed", "from_reel_no"], name: "idx_on_production_run_id_feed_from_reel_no_aaf126b47c"
    t.index ["production_run_id"], name: "index_material_loads_on_production_run_id"
    t.index ["user_id"], name: "index_material_loads_on_user_id"
    t.check_constraint "feed IN ('virgin_coex', 'virgin_mainex', 'pcw', 'regrind')", name: "material_loads_feed"
    t.check_constraint "from_reel_no > 0", name: "material_loads_from_reel_positive"
  end

  create_table "materials", force: :cascade do |t|
    t.string "name", null: false
    t.integer "material_category_id", null: false
    t.integer "supplier_id"
    t.string "grade"
    t.string "origin", default: "virgin", null: false
    t.string "source", default: "purchased", null: false
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["material_category_id"], name: "index_materials_on_material_category_id"
    t.index ["name"], name: "index_materials_on_name", unique: true
    t.index ["supplier_id"], name: "index_materials_on_supplier_id"
  end

  create_table "plan_draft_lines", force: :cascade do |t|
    t.integer "plan_draft_id", null: false
    t.integer "line_id", null: false
    t.datetime "queue_starts_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_id"], name: "index_plan_draft_lines_on_line_id"
    t.index ["plan_draft_id", "line_id"], name: "index_plan_draft_lines_on_plan_draft_id_and_line_id", unique: true
    t.index ["plan_draft_id"], name: "index_plan_draft_lines_on_plan_draft_id"
  end

  create_table "plan_drafts", force: :cascade do |t|
    t.integer "started_by_id"
    t.boolean "current", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current"], name: "index_plan_drafts_on_current", unique: true
    t.index ["started_by_id"], name: "index_plan_drafts_on_started_by_id"
    t.check_constraint "current = 1", name: "plan_drafts_one_at_a_time"
  end

  create_table "product_specs", force: :cascade do |t|
    t.string "code", null: false
    t.integer "revision", default: 1, null: false
    t.integer "customer_id"
    t.integer "width_mm", null: false
    t.integer "thickness_micron", null: false
    t.string "material_type", default: "clear", null: false
    t.boolean "pe", default: false, null: false
    t.string "silicone", default: "none", null: false
    t.integer "silicone_bp"
    t.boolean "antiblock", default: false, null: false
    t.integer "core_inches", default: 6, null: false
    t.string "core_orientation", default: "horizontal", null: false
    t.string "reel_limit", default: "max_diameter", null: false
    t.integer "max_diameter_mm"
    t.integer "max_reel_g"
    t.string "pallet_type", default: "euro", null: false
    t.integer "reels_per_pallet"
    t.boolean "label_inside_core", default: false, null: false
    t.text "packaging_notes"
    t.string "customer_part_no"
    t.string "customer_tool_no"
    t.string "customer_product_code"
    t.string "customer_description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code", "revision"], name: "index_product_specs_on_code_and_revision", unique: true
    t.index ["customer_id"], name: "index_product_specs_on_customer_id"
    t.check_constraint "revision > 0", name: "product_specs_revision_positive"
    t.check_constraint "thickness_micron > 0", name: "product_specs_thickness_positive"
    t.check_constraint "width_mm > 0", name: "product_specs_width_positive"
  end

  create_table "production_runs", force: :cascade do |t|
    t.integer "despatch_number", null: false
    t.integer "line_id", null: false
    t.integer "schedule_block_id"
    t.integer "sales_order_line_id", null: false
    t.integer "product_spec_id", null: false
    t.string "status", default: "running", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "started_by_id"
    t.string "antiblock_batch_no"
    t.string "silicone_batch_no"
    t.string "pe_film_batch_no"
    t.string "technician_days"
    t.string "technician_nights"
    t.text "special_instructions"
    t.text "comments"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "finished_by_id"
    t.index ["despatch_number"], name: "index_production_runs_on_despatch_number", unique: true
    t.index ["finished_by_id"], name: "index_production_runs_on_finished_by_id"
    t.index ["line_id", "status"], name: "index_production_runs_on_line_id_and_status"
    t.index ["line_id"], name: "index_production_runs_on_line_id"
    t.index ["line_id"], name: "index_production_runs_one_running_per_line", unique: true, where: "status = 'running'"
    t.index ["product_spec_id"], name: "index_production_runs_on_product_spec_id"
    t.index ["sales_order_line_id"], name: "index_production_runs_on_sales_order_line_id"
    t.index ["schedule_block_id"], name: "index_production_runs_on_schedule_block_id", unique: true
    t.index ["started_by_id"], name: "index_production_runs_on_started_by_id"
    t.check_constraint "despatch_number > 0", name: "production_runs_despatch_number_positive"
    t.check_constraint "ended_at IS NULL OR ended_at >= started_at", name: "production_runs_end_after_start"
  end

  create_table "purchase_order_lines", force: :cascade do |t|
    t.integer "purchase_order_id", null: false
    t.integer "material_id", null: false
    t.integer "quantity_g", null: false
    t.string "quantity_unit", default: "kg", null: false
    t.integer "price_per_tonne_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["material_id"], name: "index_purchase_order_lines_on_material_id"
    t.index ["purchase_order_id"], name: "index_purchase_order_lines_on_purchase_order_id"
    t.check_constraint "price_per_tonne_cents >= 0", name: "purchase_order_lines_price_non_negative"
    t.check_constraint "quantity_g > 0", name: "purchase_order_lines_quantity_positive"
  end

  create_table "purchase_orders", force: :cascade do |t|
    t.string "number", null: false
    t.integer "supplier_id", null: false
    t.string "currency", default: "GBP", null: false
    t.string "incoterm"
    t.string "status", default: "draft", null: false
    t.date "expected_on", null: false
    t.string "supplier_ref"
    t.text "notes"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "closed_short_at"
    t.index ["number"], name: "index_purchase_orders_on_number", unique: true
    t.index ["status", "expected_on"], name: "index_purchase_orders_on_status_and_expected_on"
    t.index ["supplier_id"], name: "index_purchase_orders_on_supplier_id"
  end

  create_table "reels", force: :cascade do |t|
    t.integer "production_run_id", null: false
    t.integer "reel_no", null: false
    t.datetime "produced_at", null: false
    t.integer "weight_g", null: false
    t.integer "length_m"
    t.integer "pallet_no"
    t.string "initials"
    t.integer "user_id"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_run_id", "reel_no"], name: "index_reels_on_production_run_id_and_reel_no", unique: true
    t.index ["production_run_id"], name: "index_reels_on_production_run_id"
    t.index ["user_id"], name: "index_reels_on_user_id"
    t.check_constraint "length_m IS NULL OR length_m > 0", name: "reels_length_positive"
    t.check_constraint "pallet_no IS NULL OR pallet_no > 0", name: "reels_pallet_positive"
    t.check_constraint "reel_no > 0", name: "reels_reel_no_positive"
    t.check_constraint "weight_g > 0", name: "reels_weight_positive"
  end

  create_table "run_checks", force: :cascade do |t|
    t.integer "production_run_id", null: false
    t.string "stage", null: false
    t.string "item", null: false
    t.boolean "passed", null: false
    t.integer "target"
    t.integer "min_value"
    t.integer "max_value"
    t.integer "actual"
    t.string "unit"
    t.integer "user_id"
    t.datetime "checked_at", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_run_id", "stage", "item"], name: "index_run_checks_on_production_run_id_and_stage_and_item"
    t.index ["production_run_id"], name: "index_run_checks_on_production_run_id"
    t.index ["user_id"], name: "index_run_checks_on_user_id"
  end

  create_table "sage_exports", force: :cascade do |t|
    t.integer "created_by_id"
    t.string "filename", null: false
    t.text "csv", null: false
    t.integer "rows_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_sage_exports_on_created_by_id"
  end

  create_table "sales_order_lines", force: :cascade do |t|
    t.integer "sales_order_id", null: false
    t.integer "product_spec_id", null: false
    t.integer "quantity_g", null: false
    t.string "customer_batch_no"
    t.integer "price_per_tonne_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "currency", default: "GBP", null: false
    t.string "quantity_unit", default: "kg", null: false
    t.index ["product_spec_id"], name: "index_sales_order_lines_on_product_spec_id"
    t.index ["sales_order_id"], name: "index_sales_order_lines_on_sales_order_id"
    t.check_constraint "price_per_tonne_cents IS NULL OR price_per_tonne_cents >= 0", name: "sales_order_lines_price_non_negative"
    t.check_constraint "quantity_g > 0", name: "sales_order_lines_quantity_positive"
  end

  create_table "sales_orders", force: :cascade do |t|
    t.string "number", null: false
    t.integer "customer_id", null: false
    t.string "customer_po_ref"
    t.date "required_on", null: false
    t.boolean "urgent", default: false, null: false
    t.string "status", default: "open", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_sales_orders_on_customer_id"
    t.index ["number"], name: "index_sales_orders_on_number", unique: true
    t.index ["status", "required_on"], name: "index_sales_orders_on_status_and_required_on"
  end

  create_table "schedule_blocks", force: :cascade do |t|
    t.integer "line_id", null: false
    t.string "kind", null: false
    t.integer "position", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.integer "duration_minutes", null: false
    t.integer "sales_order_line_id"
    t.integer "planned_g"
    t.boolean "locked", default: false, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "automatic", default: false, null: false
    t.integer "plan_draft_id"
    t.integer "source_block_id"
    t.string "colour"
    t.index ["line_id", "position"], name: "index_schedule_blocks_on_line_id_and_position"
    t.index ["line_id", "starts_at"], name: "index_schedule_blocks_on_line_id_and_starts_at"
    t.index ["line_id"], name: "index_schedule_blocks_on_line_id"
    t.index ["plan_draft_id"], name: "index_schedule_blocks_on_plan_draft_id"
    t.index ["sales_order_line_id"], name: "index_schedule_blocks_on_sales_order_line_id"
    t.index ["source_block_id"], name: "index_schedule_blocks_on_source_block_id"
    t.check_constraint "duration_minutes > 0 AND duration_minutes % 30 = 0", name: "schedule_blocks_duration_in_slots"
    t.check_constraint "ends_at > starts_at", name: "schedule_blocks_ends_after_start"
    t.check_constraint "kind <> 'job' OR (sales_order_line_id IS NOT NULL AND planned_g > 0)", name: "schedule_blocks_jobs_have_order_line"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "spec_ingredients", force: :cascade do |t|
    t.integer "product_spec_id", null: false
    t.string "feed", null: false
    t.integer "share_bp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_spec_id", "feed"], name: "index_spec_ingredients_on_product_spec_id_and_feed", unique: true
    t.index ["product_spec_id"], name: "index_spec_ingredients_on_product_spec_id"
    t.check_constraint "feed IN ('virgin_coex', 'virgin_mainex', 'pcw', 'regrind')", name: "spec_ingredients_feed"
    t.check_constraint "share_bp BETWEEN 0 AND 10000", name: "spec_ingredients_share_range"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.integer "lot_id", null: false
    t.string "kind", null: false
    t.integer "quantity_g", null: false
    t.string "from_location"
    t.string "to_location"
    t.integer "user_id"
    t.text "note"
    t.datetime "moved_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "production_run_id"
    t.boolean "bag_variance", default: false, null: false
    t.index ["lot_id", "moved_at"], name: "index_stock_movements_on_lot_id_and_moved_at"
    t.index ["lot_id"], name: "index_stock_movements_on_lot_id"
    t.index ["production_run_id"], name: "index_stock_movements_on_production_run_id"
    t.index ["user_id"], name: "index_stock_movements_on_user_id"
    t.check_constraint "(kind = 'transfer') = (quantity_g = 0)", name: "stock_movements_weight_matches_kind"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "name", null: false
    t.string "country"
    t.string "contact_name"
    t.string "email"
    t.string "phone"
    t.string "currency", default: "GBP", null: false
    t.string "incoterm"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_suppliers_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "role", default: "office", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "sign_in_anywhere", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "backup_checks", "users", column: "requested_by_id"
  add_foreign_key "delivery_note_pallets", "delivery_notes"
  add_foreign_key "delivery_note_pallets", "production_runs"
  add_foreign_key "delivery_notes", "sage_exports"
  add_foreign_key "delivery_notes", "sales_orders"
  add_foreign_key "delivery_notes", "users", column: "dispatched_by_id"
  add_foreign_key "devices", "users", column: "approved_by_id"
  add_foreign_key "devices", "users", column: "revoked_by_id"
  add_foreign_key "line_rates", "lines"
  add_foreign_key "line_rates", "product_specs"
  add_foreign_key "lots", "materials"
  add_foreign_key "lots", "purchase_order_lines"
  add_foreign_key "material_loads", "lots"
  add_foreign_key "material_loads", "production_runs"
  add_foreign_key "material_loads", "users"
  add_foreign_key "materials", "material_categories"
  add_foreign_key "materials", "suppliers"
  add_foreign_key "plan_draft_lines", "lines"
  add_foreign_key "plan_draft_lines", "plan_drafts"
  add_foreign_key "plan_drafts", "users", column: "started_by_id"
  add_foreign_key "product_specs", "customers"
  add_foreign_key "production_runs", "lines"
  add_foreign_key "production_runs", "product_specs"
  add_foreign_key "production_runs", "sales_order_lines"
  add_foreign_key "production_runs", "schedule_blocks"
  add_foreign_key "production_runs", "users", column: "finished_by_id"
  add_foreign_key "production_runs", "users", column: "started_by_id"
  add_foreign_key "purchase_order_lines", "materials"
  add_foreign_key "purchase_order_lines", "purchase_orders"
  add_foreign_key "purchase_orders", "suppliers"
  add_foreign_key "reels", "production_runs"
  add_foreign_key "reels", "users"
  add_foreign_key "run_checks", "production_runs"
  add_foreign_key "run_checks", "users"
  add_foreign_key "sage_exports", "users", column: "created_by_id"
  add_foreign_key "sales_order_lines", "product_specs"
  add_foreign_key "sales_order_lines", "sales_orders"
  add_foreign_key "sales_orders", "customers"
  add_foreign_key "schedule_blocks", "lines"
  add_foreign_key "schedule_blocks", "plan_drafts"
  add_foreign_key "schedule_blocks", "sales_order_lines"
  add_foreign_key "schedule_blocks", "schedule_blocks", column: "source_block_id", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "spec_ingredients", "product_specs"
  add_foreign_key "stock_movements", "lots"
  add_foreign_key "stock_movements", "production_runs"
  add_foreign_key "stock_movements", "users"
end
