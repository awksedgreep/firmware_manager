defmodule FirmwareManager.SNMPSimTest do
  use ExUnit.Case, async: false
  alias FirmwareManager.CMTSSNMP

  @moduletag :snmp

  # SNMPSIM is now started once globally in FirmwareManager.GlobalSetup

  test "can discover modems from CMTS" do
    port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
    assert {:ok, modems} = CMTSSNMP.discover_modems("127.0.0.1", "public", port)
    assert is_list(modems)
    assert length(modems) > 0

    # Verify modem structure
    modem = hd(modems)
    assert is_binary(modem.mac)
    assert is_binary(modem.ip)
    assert modem.status in [:online, :offline, :ranging, :other, :ranging_aborted, :ranging_complete, :ip_complete, :registration_complete, :access_denied, :unknown]
    # Verify the MAC address format
    assert String.match?(modem.mac, ~r/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/)
    # Verify the IP address format
    assert String.match?(modem.ip, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
  end

  test "can get individual modem by MAC" do
    port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
    # First get a known MAC from discovery
    {:ok, [%{mac: mac} | _]} = CMTSSNMP.discover_modems("127.0.0.1", "public", port)

    # Then try to get it directly
    assert {:ok, modem} = CMTSSNMP.get_modem("127.0.0.1", "public", mac, port)
    assert modem.mac == mac
  end

  test "returns not_found for unknown MAC" do
    port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
    assert {:error, :not_found} = CMTSSNMP.get_modem("127.0.0.1", "public", "00:00:00:00:00:00", port)
  end
end
