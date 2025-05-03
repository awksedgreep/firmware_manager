defmodule FirmwareManagerWeb.EasterEggController do
  use FirmwareManagerWeb, :controller

  def phoenix(conn, _params) do
    render(conn, :phoenix)
  end
end
