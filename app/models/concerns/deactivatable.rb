module Deactivatable
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(active: true) }
    scope :including_inactive, ->(include = true) { include ? all : active }
  end
end
