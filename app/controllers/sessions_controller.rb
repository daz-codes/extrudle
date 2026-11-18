class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  layout "auth"

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))

    if user&.active?
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private
    def after_authentication_url
      url = super
      return url unless Current.user.floor?

      # Floor users only ever see /floor, so ignore a stored office URL (such as root).
      URI(url).path.match?(%r{\A/floor(/|\z)}) ? url : floor_root_url
    end
end
