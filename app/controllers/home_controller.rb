class HomeController < ApplicationController
  require_role :admin, :office

  def show
  end
end
