defmodule FirmwareManager.ModemTest do
  use FirmwareManager.DataCase

  alias FirmwareManager.Modem

  describe "upgrade_logs" do
    alias FirmwareManager.Modem.UpgradeLog

    import FirmwareManager.ModemFixtures

    @invalid_attrs %{mac_address: nil, old_sysdescr: nil, new_sysdescr: nil, new_firmware: nil, upgraded_at: nil}

    test "list_upgrade_logs/0 returns all upgrade_logs" do
      upgrade_log = upgrade_log_fixture()
      [result] = Modem.list_upgrade_logs(id: upgrade_log.id)
      assert result.id == upgrade_log.id
      assert result.mac_address == upgrade_log.mac_address
      assert result.old_sysdescr == upgrade_log.old_sysdescr
      assert result.new_sysdescr == upgrade_log.new_sysdescr
      assert result.new_firmware == upgrade_log.new_firmware
    end

    test "get_upgrade_log!/1 returns the upgrade_log with given id" do
      upgrade_log = upgrade_log_fixture()
      result = Modem.get_upgrade_log!(upgrade_log.id)
      assert result.id == upgrade_log.id
      assert result.mac_address == upgrade_log.mac_address
      assert result.old_sysdescr == upgrade_log.old_sysdescr
      assert result.new_sysdescr == upgrade_log.new_sysdescr
      assert result.new_firmware == upgrade_log.new_firmware
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

    test "create_upgrade_log/1 with invalid data returns error" do
      assert {:error, %Ash.Error.Invalid{}} = Modem.create_upgrade_log(@invalid_attrs)
    end

    # Logs are immutable records and should not be updated or deleted individually
    # Tests for update_upgrade_log, delete_upgrade_log, and change_upgrade_log have been removed
  end
end
