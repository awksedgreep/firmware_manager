defmodule FirmwareManager.SNMP.PortAllocator do
  @moduledoc """
  Picks an available UDP port for virtual CMTS simulators.

  Strategy:
  - Gather used ports from DB (virtual CMTS) and in-memory simulator registry
  - Scan from a base port and pick the first available that is not in use and not bound
  """

  alias FirmwareManager.Modem

  @default_start 30161
  @window 400

  @registry_key :cmts_sim_registry

  @spec next_port(non_neg_integer()) :: non_neg_integer()
  def next_port(start_port \\ @default_start) do
    used = used_ports()

    start_port..(start_port + @window)
    |> Enum.find(fn port ->
      not MapSet.member?(used, port) and udp_port_available?(port)
    end)
    |> case do
      nil -> start_port
      port -> port
    end
  end

  defp used_ports do
    # DB virtual cmts ports
    db_ports =
      Modem.list_cmts(filter: [virtual: true])
      |> Enum.map(& &1.snmp_port)
      |> Enum.filter(&is_integer/1)

    # Registry ports (running simulators)
    reg_ports =
      Application.get_env(:firmware_manager, @registry_key, %{})
      |> Map.values()
      |> Enum.map(& &1.port)
      |> Enum.filter(&is_integer/1)

    MapSet.new(db_ports ++ reg_ports)
  end

  defp udp_port_available?(port) when is_integer(port) do
    case :gen_udp.open(port, [:binary, {:active, false}]) do
      {:ok, socket} ->
        :gen_udp.close(socket)
        true

      _ ->
        false
    end
  end
end
