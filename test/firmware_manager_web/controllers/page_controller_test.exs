defmodule FirmwareManagerWeb.PageControllerTest do
  use FirmwareManagerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    # Check for the Firmware Manager title instead of the default Phoenix text
    assert html_response(conn, 200) =~ "Firmware Manager"
  end
end
