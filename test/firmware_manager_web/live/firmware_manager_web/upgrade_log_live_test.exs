defmodule FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLiveTest do
  use FirmwareManagerWeb.ConnCase

  import Phoenix.LiveViewTest
  import FirmwareManager.ModemFixtures

  defp create_upgrade_log(_) do
    upgrade_log = upgrade_log_fixture()
    %{upgrade_log: upgrade_log}
  end

  describe "Index" do
    setup [:create_upgrade_log]

    test "lists all upgrade_logs", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/upgrade_logs")

      assert html =~ "Upgrade Logs"
      assert html =~ "Truncate Logs"
    end
  end
end
