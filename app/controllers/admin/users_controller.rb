class Admin::UsersController < ApplicationController
  require_role :admin
  before_action :set_user, only: %i[ edit update ]

  def index
    @users = User.by_name
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to admin_users_path, notice: "#{@user.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attributes = user_params
    attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?

    @user.assign_attributes(attributes)

    if locking_self_out?
      @user.errors.add(:base, "You can't remove your own admin access, deactivate yourself, or stop signing in anywhere from a computer that isn't approved.")
      render :edit, status: :unprocessable_content
    elsif @user.save
      end_other_sessions
      redirect_to admin_users_path, notice: "#{@user.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    # Deactivating a user or changing their password signs them out everywhere
    # (except the admin's own current session when editing themselves).
    def end_other_sessions
      return unless !@user.active? || @user.saved_change_to_password_digest?

      @user.sessions.where.not(id: Current.session.id).destroy_all
    end

    # Admins can't remove their own admin access, deactivate themselves, or
    # stop signing in anywhere while on a computer that isn't approved.
    def locking_self_out?
      @user == Current.user && (!@user.admin? || !@user.active? || (!@user.sign_in_anywhere? && !computer_approved?))
    end

    def user_params
      params.expect(user: %i[ name email_address role active sign_in_anywhere password password_confirmation ]).tap do |attributes|
        attributes[:sign_in_anywhere] = false if attributes.key?(:role) && attributes[:role] != "admin"
      end
    end
end
