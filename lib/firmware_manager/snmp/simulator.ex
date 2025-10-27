defmodule FirmwareManager.SNMP.Simulator do
  @moduledoc """
  Manages in-process SNMP simulators for virtual CMTS records using snmpkit.

  For each virtual CMTS, we start a :cmts device on the configured snmp_port and
  populate a minimal docsIfCmtsCmStatusTable with a configurable modem_count.
  """

  require Logger
  alias SnmpKit.SnmpSim.{ProfileLoader, Device}
  alias FirmwareManager.SNMP.PortAllocator

  @registry_key :cmts_sim_registry

  @doc """
  Ensure a simulator is running for a CMTS marked as virtual. Returns {:ok, port} or :noop for non-virtual.
  """
  def ensure_cmts_sim(%{id: id, virtual: true, snmp_port: port, modem_count: _count} = cmts) do
    case get_sim(id) do
      %{device: pid, port: ^port} when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, port}, else: start_and_track(cmts)

      _ ->
        start_and_track(cmts)
    end
  end

  def ensure_cmts_sim(%{virtual: false}), do: :noop

  @doc """
  Stop simulator for a given CMTS if running.
  """
  def stop_cmts_sim(%{id: id}) do
    case get_sim(id) do
      %{device: pid} ->
        _ = Device.stop(pid)
        del_sim(id)
        :ok

      _ ->
        :ok
    end
  end

  defp start_and_track(%{id: id, snmp_port: port, modem_count: count} = cmts) do
    {oid_map, modem_rows} = cmts_oid_map(count)
    {:ok, profile} = ProfileLoader.load_profile(:cmts, {:manual, oid_map})

    case Device.start_link(%{
           port: port,
           device_type: :cmts,
           device_id: "cmts_#{port}",
           community: "public",
           profile: profile
         }) do
      {:ok, device} ->
        # Start per-modem simulated devices on localhost with unique ports
        modems =
          Enum.map(modem_rows, fn %{mac_bin: mac_bin} ->
            modem_port = PortAllocator.next_port()

            {:ok, modem_dev} =
              Device.start_link(%{
                port: modem_port,
                device_type: :cable_modem,
                device_id: "modem_#{modem_port}",
                community: Map.get(cmts, :modem_snmp_write, "private")
              })

            sysdescr = "Sim Cable Modem #{format_mac(mac_bin)} v1.0"

            %{
              device: modem_dev,
              port: modem_port,
              mac_bin: mac_bin,
              mac: format_mac(mac_bin),
              sysdescr: sysdescr
            }
          end)

        put_sim(id, %{device: device, port: port, modems: modems})

        Logger.info(
          "Started virtual CMTS simulator on port #{port} with #{length(modems)} modem(s) for #{inspect(id)}"
        )

        {:ok, port}

      {:error, reason} ->
        Logger.error("Failed to start simulator on port #{port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cmts_oid_map(count) when is_integer(count) and count > 0 do
    # docsIfCmtsCmStatusTable base
    base = "1.3.6.1.2.1.10.127.1.3.3.1"
    # ARP (IP-MIB ipNetToMedia) base: ipNetToMediaTable
    # Columns we populate:
    #   ipNetToMediaPhysAddress: 1.3.6.1.2.1.4.22.1.2.ifIndex.A.B.C.D (OCTET STRING MAC)
    #   ipNetToMediaType:        1.3.6.1.2.1.4.22.1.4.ifIndex.A.B.C.D (INTEGER 3=dynamic)
    arp_phys_base = "1.3.6.1.2.1.4.22.1.2"
    arp_type_base = "1.3.6.1.2.1.4.22.1.4"
    if_index = 1

    Enum.reduce(1..count, {%{}, []}, fn idx, {acc, rows} ->
      mac = random_mac()
      ip = {192, 168, 0, 100 + idx}
      ip_bin = :erlang.list_to_binary(:erlang.tuple_to_list(ip))
      ip_suffix = ip |> Tuple.to_list() |> Enum.join(".")
      status = random_status()

      acc =
        acc
        # docsIfCmtsCmStatusTable essentials
        |> Map.put("#{base}.2.#{idx}", %{type: "OCTET STRING", value: mac})
        |> Map.put("#{base}.6.#{idx}", %{type: "INTEGER", value: status})
        # Keep legacy docsIf IP column for compatibility (runtime OCTET STRING for IPv4)
        |> Map.put("#{base}.10.#{idx}", %{type: "OCTET STRING", value: ip_bin})
        # ARP rows for MAC<->IPv4 mapping
        |> Map.put("#{arp_phys_base}.#{if_index}.#{ip_suffix}", %{
          type: "OCTET STRING",
          value: mac
        })
        |> Map.put("#{arp_type_base}.#{if_index}.#{ip_suffix}", %{type: "INTEGER", value: 3})

      rows = [%{mac_bin: mac, ip: ip, status: status} | rows]
      {acc, rows}
    end)
  end

  defp random_mac do
    :crypto.strong_rand_bytes(6)
  end

  defp format_mac(bin) when is_binary(bin) and byte_size(bin) == 6 do
    bin
    |> :binary.bin_to_list()
    |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
    |> Enum.join(":")
  end

  # Limit to 1..8 (exclude 9 :access_denied)
  defp random_status do
    Enum.random(1..8)
  end

  # Simple process registry in application env (sufficient for dev/test)
  defp get_sim(id) do
    registry = Application.get_env(:firmware_manager, @registry_key, %{})
    Map.get(registry, id)
  end

  defp put_sim(id, info) do
    registry = Application.get_env(:firmware_manager, @registry_key, %{})
    Application.put_env(:firmware_manager, @registry_key, Map.put(registry, id, info))
  end

  defp del_sim(id) do
    registry = Application.get_env(:firmware_manager, @registry_key, %{})
    Application.put_env(:firmware_manager, @registry_key, Map.delete(registry, id))
  end

  @doc """
  Return a map of mac_string => modem_port for a given CMTS.
  """
  def modem_ports(%{id: id}) do
    case get_sim(id) do
      %{modems: modems} when is_list(modems) ->
        Enum.into(modems, %{}, fn %{mac: mac, port: port} -> {String.downcase(mac), port} end)

      _ ->
        %{}
    end
  end

  @doc """
  Enrich discovered modem maps with localhost IP and simulator-assigned port when available.
  """
  def enrich_with_sim_ports(%{id: id} = _cmts, modems) when is_list(modems) do
    ports = modem_ports(%{id: id})

    Enum.map(modems, fn m ->
      case Map.fetch(ports, String.downcase(m.mac)) do
        {:ok, port} -> Map.put(m, :ip, "127.0.0.1") |> Map.put(:port, port)
        :error -> m
      end
    end)
  end

  @doc """
  Return a map of mac_string => sysdescr for a given CMTS.
  """
  def modem_sysdescrs(%{id: id}) do
    case get_sim(id) do
      %{modems: modems} when is_list(modems) ->
        Enum.into(modems, %{}, fn %{mac: mac, sysdescr: sys} -> {String.downcase(mac), sys} end)

      _ ->
        %{}
    end
  end
end
