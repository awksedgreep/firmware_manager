defmodule FirmwareManager.Snmp.ModemUpgradeTest do
  use ExUnit.Case, async: false
  alias SnmpKit.SnmpMgr

  @moduletag :snmp

  setup_all do
    # Start base simulator (CMTS) and dedicated modem device
    :ok = FirmwareManager.SnmpKitSimHelper.start_sim()
    {:ok, port} = FirmwareManager.SnmpKitSimHelper.start_modem()

    on_exit(fn ->
      :ok = FirmwareManager.SnmpKitSimHelper.stop_modem()
    end)

    {:ok, %{port: port}}
  end

  test "modem firmware upgrade flow via SET and polling", %{port: port} do
    target = "127.0.0.1:#{port}"
    ro = "public"
    rw = "public" # if sim enforces separate communities, adjust accordingly

    server_oid = [1,3,6,1,2,1,69,1,3,3,0]
    file_oid   = [1,3,6,1,2,1,69,1,3,4,0]
    admin_oid  = [1,3,6,1,2,1,69,1,3,1,0]
    oper_oid   = [1,3,6,1,2,1,69,1,3,2,0]

    # Prime
    assert {:ok, _} = SnmpMgr.set(target, server_oid, "10.0.0.5", community: rw, version: :v2c)
    assert {:ok, _} = SnmpMgr.set(target, file_oid, "cm-fw-1.2.3.bin", community: rw, version: :v2c)

    # Trigger (value 3 commonly used for upgrade-from-mgt-sw; sim should accept documented trigger enum)
    assert {:ok, _} = SnmpMgr.set(target, admin_oid, 3, community: rw, version: :v2c)

    # Poll oper status until success or failure
    status =
      1..30
      |> Enum.reduce_while(:unknown, fn _, acc ->
        Process.sleep(200)

        case SnmpMgr.get_with_type(target, oper_oid, community: ro, version: :v2c) do
          {:ok, {_oid, _type, val}} when val in [4, 5] -> # accept 4=ok or other success code per sim
            {:halt, :ok}

          {:ok, {_oid, _type, 9}} -> # failed
            {:halt, :failed}

          _ ->
            {:cont, acc}
        end
      end)

    assert status == :ok
  end
end

