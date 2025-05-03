defmodule FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLiveTest do
  use FirmwareManagerWeb.ConnCase

  import Phoenix.LiveViewTest
  import FirmwareManager.ModemFixtures

  @create_attrs %{mac_address: "some mac_address", old_sysdescr: "some old_sysdescr", new_sysdescr: "some new_sysdescr", new_firmware: "some new_firmware", upgraded_at: "2025-05-02T05:14:00Z"}
  @update_attrs %{mac_address: "some updated mac_address", old_sysdescr: "some updated old_sysdescr", new_sysdescr: "some updated new_sysdescr", new_firmware: "some updated new_firmware", upgraded_at: "2025-05-03T05:14:00Z"}
  @invalid_attrs %{mac_address: nil, old_sysdescr: nil, new_sysdescr: nil, new_firmware: nil, upgraded_at: nil}

  defp create_upgrade_log(_) do
    upgrade_log = upgrade_log_fixture()
    %{upgrade_log: upgrade_log}
  end

  describe "Index" do
    setup [:create_upgrade_log]

    test "lists all upgrade_logs", %{conn: conn, upgrade_log: upgrade_log} do
      {:ok, _index_live, html} = live(conn, ~p"/firmware_manager_web/upgrade_logs")

      assert html =~ "Listing Upgrade logs"
      assert html =~ upgrade_log.mac_address
    end

    test "saves new upgrade_log", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/firmware_manager_web/upgrade_logs")

      assert index_live |> element("a", "New Upgrade log") |> render_click() =~
               "New Upgrade log"

      assert_patch(index_live, ~p"/firmware_manager_web/upgrade_logs/new")

      assert index_live
             |> form("#upgrade_log-form", upgrade_log: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#upgrade_log-form", upgrade_log: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/firmware_manager_web/upgrade_logs")

      html = render(index_live)
      assert html =~ "Upgrade log created successfully"
      assert html =~ "some mac_address"
    end

    test "updates upgrade_log in listing", %{conn: conn, upgrade_log: upgrade_log} do
      {:ok, index_live, _html} = live(conn, ~p"/firmware_manager_web/upgrade_logs")

      assert index_live |> element("#upgrade_logs-#{upgrade_log.id} a", "Edit") |> render_click() =~
               "Edit Upgrade log"

      assert_patch(index_live, ~p"/firmware_manager_web/upgrade_logs/#{upgrade_log}/edit")

      assert index_live
             |> form("#upgrade_log-form", upgrade_log: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#upgrade_log-form", upgrade_log: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/firmware_manager_web/upgrade_logs")

      html = render(index_live)
      assert html =~ "Upgrade log updated successfully"
      assert html =~ "some updated mac_address"
    end

    test "deletes upgrade_log in listing", %{conn: conn, upgrade_log: upgrade_log} do
      {:ok, index_live, _html} = live(conn, ~p"/firmware_manager_web/upgrade_logs")

      assert index_live |> element("#upgrade_logs-#{upgrade_log.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#upgrade_logs-#{upgrade_log.id}")
    end
  end

  describe "Show" do
    setup [:create_upgrade_log]

    test "displays upgrade_log", %{conn: conn, upgrade_log: upgrade_log} do
      {:ok, _show_live, html} = live(conn, ~p"/firmware_manager_web/upgrade_logs/#{upgrade_log}")

      assert html =~ "Show Upgrade log"
      assert html =~ upgrade_log.mac_address
    end

    test "updates upgrade_log within modal", %{conn: conn, upgrade_log: upgrade_log} do
      {:ok, show_live, _html} = live(conn, ~p"/firmware_manager_web/upgrade_logs/#{upgrade_log}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Upgrade log"

      assert_patch(show_live, ~p"/firmware_manager_web/upgrade_logs/#{upgrade_log}/show/edit")

      assert show_live
             |> form("#upgrade_log-form", upgrade_log: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#upgrade_log-form", upgrade_log: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/firmware_manager_web/upgrade_logs/#{upgrade_log}")

      html = render(show_live)
      assert html =~ "Upgrade log updated successfully"
      assert html =~ "some updated mac_address"
    end
  end
end
