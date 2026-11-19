# Only approved computers can use Extrudle (PLAN.md Slice 8a), when
# Device.required?. Runs after sign-in on every request, so revoking a
# computer signs it out at once. A user who can sign in anywhere (Stu) can
# use any computer, and approve it.
#
# The sign-in and password reset pages skip the check: anyone can reset their
# password from anywhere, but only "sign in anywhere" users can sign in on an
# unapproved computer (SessionsController).
module ApprovedComputers
  extend ActiveSupport::Concern

  included do
    before_action :require_approved_computer
    helper_method :current_device, :computer_approved?
  end

  class_methods do
    def allow_unapproved_computers(**options)
      skip_before_action :require_approved_computer, **options
    end
  end

  private
    def current_device
      return @current_device if defined?(@current_device)

      @current_device = Device.find_by_token(cookies.signed[Device::COOKIE])&.tap { _1.seen!(ip: request.remote_ip) }
    end

    def computer_approved?
      !Device.required? || current_device.present?
    end

    def require_approved_computer
      return if computer_approved? || Current.user&.sign_in_anywhere?

      terminate_session if Current.session
      render "computers/not_approved", layout: "auth", status: :forbidden
    end

    def remember_device(device)
      cookies.signed.permanent[Device::COOKIE] = { value: device.token, httponly: true, same_site: :lax, secure: Rails.env.production? }
    end
end
