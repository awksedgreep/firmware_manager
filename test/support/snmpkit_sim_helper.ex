defmodule FirmwareManager.SnmpKitSimHelper do
  @moduledoc """
  Test helper to run an in-process SNMP simulator using snmpkit.

  This replaces the prior external snmpsim container approach.
  """

  require Logger
  alias SnmpKit.SnmpSim.{ProfileLoader, Device}

  @app :firmware_manager
  @env_key :snmpkit_sim_helper

  # Public API

  @doc """
  Start a dedicated cable_modem device for upgrade tests.
  Returns {:ok, port}.
  """
  def start_modem do
    case Application.get_env(@app, @env_key) do
      %{modem: %{device: device, port: port}} when is_pid(device) ->
        {:ok, port}

      current when is_map(current) ->
        port = find_available_udp_port(11_261, 11_361)

        {:ok, device} =
          Device.start_link(%{
            port: port,
            device_type: :cable_modem,
            device_id: "cable_modem_#{port}",
            community: "public"
          })

        Application.put_env(@app, @env_key, Map.put(current, :modem, %{device: device, port: port}))
        {:ok, port}

      _ ->
        port = find_available_udp_port(11_261, 11_361)

        {:ok, device} =
          Device.start_link(%{
            port: port,
            device_type: :cable_modem,
            device_id: "cable_modem_#{port}",
            community: "public"
          })

        Application.put_env(@app, @env_key, %{modem: %{device: device, port: port}})
        {:ok, port}
    end
  end

  @doc """
  Stop the dedicated modem device if running.
  """
  def stop_modem do
    case Application.get_env(@app, @env_key) do
      %{modem: %{device: device}} = env ->
        _ = Device.stop(device)
        Application.put_env(@app, @env_key, Map.delete(env, :modem))
        :ok

      _ -> :ok
    end
  end

  @doc """
  Start the snmpkit simulator once for the test run.
  """
  def start_sim do
    case Application.get_env(@app, @env_key) do
      %{device: device, port: port} when is_pid(device) ->
        Logger.info("snmpkit simulator already running on port #{port}")
        :ok

      _ ->
        port = find_available_udp_port(11_161, 12_161)

        {:ok, profile} = ProfileLoader.load_profile(:cmts, {:manual, cmts_oid_map()})

        device = start_device(profile, port)

        Application.put_env(@app, @env_key, %{device: device, port: port})
        Logger.info("snmpkit simulator started on port #{port}")
        :ok
    end
  end

  @doc """
  Stop the simulator if it is running.
  """
  def stop_sim do
    case Application.get_env(@app, @env_key) do
      %{device: device} ->
        _ = Device.stop(device)
        Application.delete_env(@app, @env_key)
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Return the UDP port the simulator is listening on.
  """
  def get_port do
    case Application.get_env(@app, @env_key) do
      %{port: port} -> port
      _ -> raise "SNMP simulator not started"
    end
  end

  # Internal helpers

  defp start_device(profile, port) do
    case Code.ensure_loaded(SnmpKit.Sim) do
      {:module, SnmpKit.Sim} ->
        {:ok, device} = SnmpKit.Sim.start_device(profile, port: port, community: "public")
        device

      _ ->
        {:ok, device} =
          Device.start_link(%{
            port: port,
            device_type: :cmts,
            device_id: "cmts_#{port}",
            community: "public",
            profile: profile
          })

        device
    end
  end

  defp find_available_udp_port(start_port, end_port) do
    start_port..end_port
    |> Enum.find(fn p ->
      case :gen_udp.open(p, [:binary, {:active, false}]) do
        {:ok, socket} ->
          :gen_udp.close(socket)
          true

        _ ->
          false
      end
    end)
    |> case do
      nil -> raise "No available UDP port in #{start_port}-#{end_port}"
      port -> port
    end
  end

  # Build a minimal docsIfCmtsCmStatusTable with 4 rows
  # Columns used by the app:
  #  - .2.<idx>: docsIfCmtsCmStatusMacAddress (OCTET STRING, 6 bytes)
  #  - .6.<idx>: docsIfCmtsCmStatusValue (INTEGER per RFC mapping)
  #  - .10.<idx>: docsIfCmtsCmStatusInetAddress (OCTET STRING, 4 bytes IPv4)
  defp cmts_oid_map do
    base = "1.3.6.1.2.1.10.127.1.3.3.1"
    arp_phys_base = "1.3.6.1.2.1.4.22.1.2"
    arp_type_base = "1.3.6.1.2.1.4.22.1.4"
    if_index = 1

    m1 = <<0x00, 0x11, 0x22, 0x33, 0x44, 0x55>>
    m2 = <<0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB>>
    m3 = <<0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE>>
    m4 = <<0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC>>

    i1 = <<192, 168, 0, 10>>
    i2 = <<192, 168, 0, 11>>
    i3 = <<192, 168, 0, 12>>
    i4 = <<192, 168, 0, 13>>

    %{}
    # docsIf
    |> put_mac("#{base}.2.1", m1)
    |> put_status("#{base}.6.1", 8) # online
    |> put_ip("#{base}.10.1", i1)
    |> put_mac("#{base}.2.2", m2)
    |> put_status("#{base}.6.2", 2) # offline
    |> put_ip("#{base}.10.2", i2)
    |> put_mac("#{base}.2.3", m3)
    |> put_status("#{base}.6.3", 5) # ranging_complete
    |> put_ip("#{base}.10.3", i3)
    |> put_mac("#{base}.2.4", m4)
    |> put_status("#{base}.6.4", 8) # online
    |> put_ip("#{base}.10.4", i4)
    # ARP rows (ipNetToMedia)
    |> put_arp_row(arp_phys_base, arp_type_base, if_index, i1, m1)
    |> put_arp_row(arp_phys_base, arp_type_base, if_index, i2, m2)
    |> put_arp_row(arp_phys_base, arp_type_base, if_index, i3, m3)
    |> put_arp_row(arp_phys_base, arp_type_base, if_index, i4, m4)
  end

  defp put_arp_row(map, arp_phys_base, arp_type_base, if_index, ip_bin, mac_bin)
       when is_binary(ip_bin) and byte_size(ip_bin) == 4 and is_binary(mac_bin) and byte_size(mac_bin) == 6 do
    dotted = ip_bin |> :binary.bin_to_list() |> Enum.join(".")
    map
    |> Map.put("#{arp_phys_base}.#{if_index}.#{dotted}", %{type: "OCTET STRING", value: mac_bin})
    |> Map.put("#{arp_type_base}.#{if_index}.#{dotted}", %{type: "INTEGER", value: 3})
  end

  defp put_mac(map, oid, bin) when is_binary(bin) and byte_size(bin) == 6 do
    Map.put(map, oid, %{type: "OCTET STRING", value: bin})
  end

  defp put_ip(map, oid, bin) when is_binary(bin) and byte_size(bin) == 4 do
    Map.put(map, oid, %{type: "OCTET STRING", value: bin})
  end

  defp put_status(map, oid, int) when is_integer(int) do
    Map.put(map, oid, %{type: "INTEGER", value: int})
  end
end
