defmodule FirmwareManager.CMTS.UptimeTest do
  use ExUnit.Case, async: true
  alias FirmwareManager.CMTSSNMP

  describe "format_uptime/1" do
    test "formats zero seconds" do
      assert CMTSSNMP.format_uptime(0) == "0 seconds"
    end

    test "formats single second" do
      assert CMTSSNMP.format_uptime(100) == "1 second"
    end

    test "formats multiple seconds" do
      assert CMTSSNMP.format_uptime(250) == "2 seconds"
    end

    test "formats minutes and seconds" do
      assert CMTSSNMP.format_uptime(6_000) == "1 minute, 0 seconds"
    end

    test "formats hours, minutes, and seconds" do
      assert CMTSSNMP.format_uptime(366_100) == "1 hour, 1 minute, 1 second"
    end

    test "formats days, hours, minutes, and seconds" do
      assert CMTSSNMP.format_uptime(9_006_100) == "1 day, 1 hour, 1 minute, 1 second"
    end
  end
end

defmodule FirmwareManager.CMTS.SNMPTest do
  use ExUnit.Case, async: false
  alias FirmwareManager.CMTSSNMP

  # Test data
  @test_ip "127.0.0.1"
  @test_community "public" # Using public community as defined in our SNMPSIM data file

  # SNMPSIM is now started once globally in FirmwareManager.GlobalSetup
  
  describe "discover_modems/3" do
    test "discovers modems from SNMPSIM" do
      port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
      {:ok, modems} = CMTSSNMP.discover_modems(@test_ip, @test_community, port)
      assert is_list(modems)
      assert length(modems) > 0
      
      # Verify we have the expected number of modems
      assert length(modems) == 4
      
      # Verify we have both online and offline modems
      statuses = Enum.map(modems, & &1.status)
      assert :online in statuses
      assert :offline in statuses
    end
  end

  describe "get_modem/4" do
    test "returns not_found for unknown MAC address" do
      port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
      assert {:error, :not_found} = CMTSSNMP.get_modem(@test_ip, @test_community, "00:00:00:00:00:00", port)
    end
    
    test "finds a modem by MAC address" do
      port = FirmwareManager.SNMPSimHelper.get_snmpsim_port()
      # First discover modems to get a valid MAC
      {:ok, modems} = CMTSSNMP.discover_modems(@test_ip, @test_community, port)
      %{mac: mac} = hd(modems)
      
      # Then try to get that specific modem
      assert {:ok, modem} = CMTSSNMP.get_modem(@test_ip, @test_community, mac, port)
      assert modem.mac == mac
    end
  end
end
