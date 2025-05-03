defmodule FirmwareManager.ModemTest do
  use FirmwareManager.DataCase

  alias FirmwareManager.Modem

  describe "upgrade_logs" do
    alias FirmwareManager.Modem.UpgradeLog

    import FirmwareManager.ModemFixtures

    @invalid_attrs %{mac_address: nil, old_sysdescr: nil, new_sysdescr: nil, new_firmware: nil, upgraded_at: nil}

    test "list_upgrade_logs/0 returns all upgrade_logs" do
      upgrade_log = upgrade_log_fixture()
      assert Modem.list_upgrade_logs() == [upgrade_log]
    end

    test "get_upgrade_log!/1 returns the upgrade_log with given id" do
      upgrade_log = upgrade_log_fixture()
      assert Modem.get_upgrade_log!(upgrade_log.id) == upgrade_log
    end

    test "create_upgrade_log/1 with valid data creates a upgrade_log" do
      valid_attrs = %{mac_address: "some mac_address", old_sysdescr: "some old_sysdescr", new_sysdescr: "some new_sysdescr", new_firmware: "some new_firmware", upgraded_at: ~U[2025-05-02 05:14:00Z]}

      assert {:ok, %UpgradeLog{} = upgrade_log} = Modem.create_upgrade_log(valid_attrs)
      assert upgrade_log.mac_address == "some mac_address"
      assert upgrade_log.old_sysdescr == "some old_sysdescr"
      assert upgrade_log.new_sysdescr == "some new_sysdescr"
      assert upgrade_log.new_firmware == "some new_firmware"
      assert upgrade_log.upgraded_at == ~U[2025-05-02 05:14:00Z]
    end

    test "create_upgrade_log/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Modem.create_upgrade_log(@invalid_attrs)
    end

    test "update_upgrade_log/2 with valid data updates the upgrade_log" do
      upgrade_log = upgrade_log_fixture()
      update_attrs = %{mac_address: "some updated mac_address", old_sysdescr: "some updated old_sysdescr", new_sysdescr: "some updated new_sysdescr", new_firmware: "some updated new_firmware", upgraded_at: ~U[2025-05-03 05:14:00Z]}

      assert {:ok, %UpgradeLog{} = upgrade_log} = Modem.update_upgrade_log(upgrade_log, update_attrs)
      assert upgrade_log.mac_address == "some updated mac_address"
      assert upgrade_log.old_sysdescr == "some updated old_sysdescr"
      assert upgrade_log.new_sysdescr == "some updated new_sysdescr"
      assert upgrade_log.new_firmware == "some updated new_firmware"
      assert upgrade_log.upgraded_at == ~U[2025-05-03 05:14:00Z]
    end

    test "update_upgrade_log/2 with invalid data returns error changeset" do
      upgrade_log = upgrade_log_fixture()
      assert {:error, %Ecto.Changeset{}} = Modem.update_upgrade_log(upgrade_log, @invalid_attrs)
      assert upgrade_log == Modem.get_upgrade_log!(upgrade_log.id)
    end

    test "delete_upgrade_log/1 deletes the upgrade_log" do
      upgrade_log = upgrade_log_fixture()
      assert {:ok, %UpgradeLog{}} = Modem.delete_upgrade_log(upgrade_log)
      assert_raise Ecto.NoResultsError, fn -> Modem.get_upgrade_log!(upgrade_log.id) end
    end

    test "change_upgrade_log/1 returns a upgrade_log changeset" do
      upgrade_log = upgrade_log_fixture()
      assert %Ecto.Changeset{} = Modem.change_upgrade_log(upgrade_log)
    end
  end
end
