defmodule FirmwareManagerWeb.PageController do
  use FirmwareManagerWeb, :controller

  def home(conn, _params) do
    # Use the app layout to share the header across all pages
    render(conn, :home)
  end
end
