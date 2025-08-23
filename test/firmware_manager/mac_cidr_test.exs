defmodule FirmwareManager.MacCIDRTest do
  use ExUnit.Case, async: true
  alias FirmwareManager.MacCIDR

  test "parse and match CIDR length" do
    {:ok, rule} = MacCIDR.parse("aa:bb:cc:00:00:00/24")
    assert MacCIDR.match?("AA:BB:CC:12:34:56", rule)
    refute MacCIDR.match?("AA:BB:CD:12:34:56", rule)
  end

  test "parse and match explicit mask" do
    {:ok, rule} = MacCIDR.parse("aa:bb:cc:00:00:00/ff:ff:ff:00:00:00")
    assert MacCIDR.match?("aa-bb-cc-ff-ee-dd", rule)
    refute MacCIDR.match?("aa-bb-cd-ff-ee-dd", rule)
  end

  test "filter modems" do
    mods = [
      %{mac: "aa:bb:cc:00:00:01"},
      %{mac: "aa:bb:cd:00:00:01"}
    ]

    filtered = MacCIDR.filter_modems(mods, "aa:bb:cc:00:00:00/24")
    assert length(filtered) == 1
    assert hd(filtered).mac == "aa:bb:cc:00:00:01"
  end

  test "int_to_mac and mac_to_int round trip" do
    mac = "01:23:45:67:89:ab"
    {:ok, int} = MacCIDR.mac_to_int(mac)
    assert MacCIDR.int_to_mac(int) == mac
  end
end
