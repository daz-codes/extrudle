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
  end

  get "floor" => "floor#show", as: :floor_root

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
