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
      @user.errors.add(:base, "You can't remove your own admin access or deactivate yourself.")
      render :edit, status: :unprocessable_content
    elsif @user.save
      @user.sessions.destroy_all unless @user.active?
      redirect_to admin_users_path, notice: "#{@user.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    def locking_self_out?
      @user == Current.user && (!@user.admin? || !@user.active?)
    end

    def user_params
      params.expect(user: %i[ name email_address role active password password_confirmation ])
    end
end
