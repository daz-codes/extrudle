Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  namespace :admin do
    resources :users, only: %i[ index new create edit update ]
  end

  resource :master_data, only: :show, controller: "master_data"
  resources :customers, except: :destroy
  resources :suppliers, only: %i[ index new create edit update ]
  resources :material_categories, only: %i[ index new create edit update ]
  resources :materials, only: %i[ index new create edit update ]
  resources :lines, only: %i[ index new create edit update ]
  resources :product_specs, except: :destroy do
    resources :line_rates, only: %i[ create update destroy ]
    get :summary, on: :member
  end

  resources :sales_orders, path: "orders", except: :destroy do
    member do
      patch :cancel
      patch :reopen
    end
    resources :lines, controller: "sales_order_lines", only: %i[ create edit update destroy ]
  end

  resources :purchase_orders, path: "purchasing", except: :destroy do
    member do
      patch :mark_sent
      patch :back_to_draft
      patch :cancel
      patch :reopen
      patch :close_short
    end
    resources :lines, controller: "purchase_order_lines", only: %i[ create edit update destroy ]
    resources :receipts, controller: "goods_receipts", only: %i[ new create ]
  end

  get "stock" => "stock#show", as: :stock
  resources :lots, path: "stock/lots", only: %i[ index show new create ] do
    get :labels, on: :collection
    patch :move, on: :member
    resource :adjustment, controller: "lot_adjustments", only: %i[ new create ]
  end

  get "planner" => "planner#show", as: :planner
  get "planner/print" => "planner#print", as: :planner_print
  resources :schedule_blocks, path: "planner/blocks", only: %i[ create edit update destroy ] do
    patch :move, on: :member
  end

  resources :production_runs, path: "production", except: :destroy do
    resources :checks, controller: "run_checks", only: :create
  end

  get "floor" => "floor#show", as: :floor_root

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
