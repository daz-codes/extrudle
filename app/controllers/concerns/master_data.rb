# Shared behaviour for the master-data screens: office/admin only,
# a search box and an "include inactive" filter on the index.
module MasterData
  extend ActiveSupport::Concern

  included do
    require_role :admin, :office
    helper_method :include_inactive?, :search_query
  end

  private
    def include_inactive?
      params[:inactive] == "1"
    end

    def search_query
      params[:q].to_s.strip.presence
    end
end
