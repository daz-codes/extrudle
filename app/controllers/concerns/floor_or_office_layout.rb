# Pages used on the plant floor and in the office: floor users get the large
# type floor layout, everyone else the office layout.
module FloorOrOfficeLayout
  extend ActiveSupport::Concern

  included do
    layout -> { Current.user&.floor? ? "floor" : "application" }
  end
end
