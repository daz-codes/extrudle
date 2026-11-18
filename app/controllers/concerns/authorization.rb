module Authorization
  extend ActiveSupport::Concern

  class_methods do
    # require_role :admin
    # require_role :admin, :office, only: %i[ new create ]
    def require_role(*roles, **options)
      before_action(**options) { require_role!(roles) }
    end
  end

  private
    def require_role!(roles)
      return if roles.map(&:to_s).include?(Current.user&.role)

      if Current.user&.floor?
        redirect_to floor_root_path, alert: "That page is for office users."
      else
        redirect_to root_path, alert: "You don't have access to that page."
      end
    end
end
