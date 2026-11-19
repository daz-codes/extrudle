# Admin › Computers: approve the computer you're on, rename and revoke others.
# A computer can only be approved from itself, by an admin signed in on it:
# on an unapproved computer that's a "sign in anywhere" admin (Stu).
# Working assumption, see PLAN.md §11 Q56.
class Admin::DevicesController < ApplicationController
  require_role :admin
  before_action :set_device, only: %i[ edit update revoke ]

  def index
    @devices = Device.includes(:approved_by, :revoked_by).order(Arel.sql("revoked_at IS NOT NULL"), :name)
    @device = Device.new(name: suggested_name)
  end

  def create
    if current_device
      return redirect_to admin_devices_path, alert: "This computer is already approved as #{current_device.name}."
    end

    device = Device.approve!(name: params.dig(:device, :name), approved_by: Current.user, user_agent: request.user_agent, ip: request.remote_ip)
    remember_device(device)
    redirect_to admin_devices_path, notice: "This computer is approved as #{device.name}."
  rescue ActiveRecord::RecordInvalid => e
    @devices = Device.includes(:approved_by, :revoked_by).order(:name)
    @device = e.record
    render :index, status: :unprocessable_content
  end

  def edit
  end

  def update
    if @device.update(params.expect(device: [ :name ]))
      redirect_to admin_devices_path, notice: "Renamed to #{@device.name}."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Signs that computer out at once: every request checks it.
  def revoke
    @device.revoke!(by: Current.user)
    redirect_to admin_devices_path, notice: "#{@device.name} can no longer use Extrudle.", status: :see_other
  end

  private
    def set_device
      @device = Device.find(params[:id])
    end

    # "Chrome on Windows" from the browser, as a starting point for the name.
    def suggested_name
      agent = request.user_agent.to_s
      browser = %w[ Edge Chrome Firefox Safari ].detect { agent.include?(_1 == "Edge" ? "Edg/" : _1) }
      system = { "Windows" => "Windows", "Mac OS" => "Mac", "iPad" => "iPad", "iPhone" => "iPhone", "Android" => "Android", "Linux" => "Linux" }
        .detect { |key, _| agent.include?(key) }&.last
      [ browser, system ].compact.join(" on ").presence
    end
end
