defmodule FirmwareManagerWeb.EasterEggController do
  use FirmwareManagerWeb, :controller

  def phoenix(conn, _params) do
    # The app layout will be used automatically
    render(conn, :phoenix)
  end
end
