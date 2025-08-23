defmodule FirmwareManager.CMTSSNMP do
  @moduledoc """
  Module for interacting with CMTS devices via SNMP.

  This module provides functionality to discover modems connected to a CMTS
  and retrieve information about them using SNMP.
  """

  require Logger

  @default_snmp_port 161
  @default_community "public"

  # OID for docsIfCmtsCmStatusTable (RFC 3636)
  @docs_if_cmts_cm_status_table [1, 3, 6, 1, 2, 1, 10, 127, 1, 3, 3, 1]
  
  # Specific column OIDs we care about
  @docs_if_cmts_cm_status_mac_address @docs_if_cmts_cm_status_table ++ [2]
  @docs_if_cmts_cm_status_value @docs_if_cmts_cm_status_table ++ [6]
  @docs_if_cmts_cm_status_inet_address @docs_if_cmts_cm_status_table ++ [10]

  # Status code mappings
  @status_codes %{
    1 => :other,
    2 => :offline,
    3 => :ranging,
    4 => :ranging_aborted,
    5 => :ranging_complete,
    6 => :ip_complete,
    7 => :registration_complete,
    8 => :online,
    9 => :access_denied
  }

  @type ip_address :: :inet.ip_address() | String.t()
  @type port_number :: :inet.port_number()
  @type community :: String.t()
  @type modem :: %{
    mac: String.t(),
    ip: String.t(),
    status: atom()
  }

  @doc """
  Discovers all modems connected to the CMTS by walking only the necessary columns.
  This is optimized for large CMTS tables with many modems.

  ## Parameters
    - `ip`: The IP address of the CMTS
    - `community`: SNMP community string (default: "public")
    - `port`: SNMP port (default: 161)

  ## Returns
    - `{:ok, [modem()]}` on success
    - `{:error, reason}` on failure
  """
  @spec discover_modems(ip_address, community, port_number) :: {:ok, [modem()]} | {:error, any()}
  def discover_modems(ip, community \\ @default_community, port \\ @default_snmp_port) do
    target = "#{ip}:#{port}"
    opts = [community: community, version: :v2c]

    with {:ok, mac_column} <- SnmpKit.SnmpMgr.walk(target, @docs_if_cmts_cm_status_mac_address, opts),
         {:ok, status_column} <- SnmpKit.SnmpMgr.walk(target, @docs_if_cmts_cm_status_value, opts) do
      mac_map = column_to_index_map(mac_column)
      status_map = column_to_index_map(status_column)

      # Prefer non-deprecated IP derivation via ARP (ipNetToMedia). Fallback to legacy docsIf IP column if available.
      arp_phys_oid = [1, 3, 6, 1, 2, 1, 4, 22, 1, 2]
      arp_entries = case SnmpKit.SnmpMgr.walk(target, arp_phys_oid, opts) do
        {:ok, rows} -> rows
        _ -> []
      end
      arp_mac_to_ips = arp_entries_to_mac_to_ips(arp_entries)

      ip_map = case SnmpKit.SnmpMgr.walk(target, @docs_if_cmts_cm_status_inet_address, opts) do
        {:ok, ip_col} -> column_to_index_map(ip_col)
        _ -> %{}
      end

      modems = combine_with_arp(mac_map, status_map, ip_map, arp_mac_to_ips)
      {:ok, modems}
    else
      {:error, reason} ->
        Logger.error("SNMP walk failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Convert a walked column into index=>value map. Input entries are {oid_string, type, value}
  defp column_to_index_map(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn {oid_str, _type, value}, acc ->
      case SnmpKit.SnmpLib.OID.string_to_list(oid_str) do
        {:ok, oid_list} ->
          index = List.last(oid_list)
          Map.put(acc, index, value)
        _ -> acc
      end
    end)
  end

  # Build a map of MAC(binary) => ["a.b.c.d", ...] from ipNetToMediaPhysAddress entries
  defp arp_entries_to_mac_to_ips(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn {oid_str, _type, mac_bin}, acc ->
      case SnmpKit.SnmpLib.OID.string_to_list(oid_str) do
        {:ok, oid_list} ->
          # ipNetToMediaPhysAddress index: ifIndex.A.B.C.D; extract last 4 as IPv4
          ip = oid_list |> Enum.slice(-4, 4) |> Enum.join(".")
          Map.update(acc, mac_bin, [ip], fn ips -> [ip | ips] end)
        _ -> acc
      end
    end)
  end

  # Combines data from docsIf columns and ARP-derived MAC->IP mapping
  @spec combine_with_arp(map(), map(), map(), map()) :: [modem()]
  defp combine_with_arp(mac_addresses, status_values, ip_addresses, arp_mac_to_ips) do
    all_indices =
      [mac_addresses, status_values]
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()
      |> MapSet.to_list()

    Enum.map(all_indices, fn index ->
      mac_bin = Map.get(mac_addresses, index)
      mac =
        case mac_bin do
          bin when is_binary(bin) ->
            try do
              bin
              |> :binary.bin_to_list()
              |> Enum.map(&Integer.to_string(&1, 16) |> String.pad_leading(2, "0"))
              |> Enum.join(":")
            rescue
              _ -> "00:00:00:00:00:00"
            end
          other ->
            Logger.warning("Unexpected MAC address format: #{inspect(other)}")
            "unknown"
        end

      # Prefer ARP-derived IP; fallback to legacy docsIf column if present
      ip_from_arp =
        case Map.get(arp_mac_to_ips, mac_bin, []) do
          [h | _] -> h
          _ -> nil
        end

      ip_from_docsif =
        case Map.get(ip_addresses, index) do
          bin when is_binary(bin) and byte_size(bin) == 4 ->
            try do
              bin |> :binary.bin_to_list() |> Enum.join(".")
            rescue
              _ -> "0.0.0.0"
            end
          list when is_list(list) ->
            if Enum.all?(list, &is_integer/1) do
              Enum.join(list, ".")
            else
              Logger.warning("Unexpected IP address list format: #{inspect(list)}")
              "0.0.0.0"
            end
          other when not is_nil(other) ->
            Logger.warning("Unexpected IP address format: #{inspect(other)}")
            "0.0.0.0"
          _ -> nil
        end

      ip = ip_from_arp || ip_from_docsif || "0.0.0.0"

      status_val = Map.get(status_values, index, 0)
      status = Map.get(@status_codes, status_val, :unknown)

      %{mac: mac, ip: ip, status: status}
    end)
  end

  # Combines data from multiple column walks into a list of modem maps.
  @spec combine_column_data(map(), map(), map()) :: [modem()]
  defp combine_column_data(mac_addresses, status_values, ip_addresses) do
    all_indices =
      [mac_addresses, status_values, ip_addresses]
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()

    Enum.map(all_indices, fn index ->
      mac =
        case Map.get(mac_addresses, index) do
          # snmpkit typically returns binaries for OCTET STRINGs
          bin when is_binary(bin) ->
            try do
              bin
              |> :binary.bin_to_list()
              |> Enum.map(&Integer.to_string(&1, 16) |> String.pad_leading(2, "0"))
              |> Enum.join(":")
            rescue
              e ->
                Logger.error("Error parsing MAC address: #{inspect(bin)} error: #{inspect(e)}")
                "00:00:00:00:00:00"
            end
          other ->
            Logger.warning("Unexpected MAC address format: #{inspect(other)}")
            "unknown"
        end

      ip =
        case Map.get(ip_addresses, index) do
          bin when is_binary(bin) and byte_size(bin) == 4 ->
            try do
              bin |> :binary.bin_to_list() |> Enum.join(".")
            rescue
              e ->
                Logger.error("Error parsing IP address: #{inspect(bin)} error: #{inspect(e)}")
                "0.0.0.0"
            end
          list when is_list(list) ->
            # Sometimes IPs may already be presented as a list
            if Enum.all?(list, &is_integer/1) do
              Enum.join(list, ".")
            else
              Logger.warning("Unexpected IP address list format: #{inspect(list)}")
              "0.0.0.0"
            end
          other ->
            Logger.warning("Unexpected IP address format: #{inspect(other)}")
            "0.0.0.0"
        end

      status_val = Map.get(status_values, index, 0)
      status = Map.get(@status_codes, status_val, :unknown)

      %{mac: mac, ip: ip, status: status}
    end)
  end

  @doc """
  Gets information about a specific modem by MAC address.
  """
  @spec get_modem(ip_address, community, String.t(), port_number) ::
          {:ok, modem()} | {:error, :not_found} | {:error, any()}
  def get_modem(ip, community \\ @default_community, mac_address, port \\ @default_snmp_port) do
    case discover_modems(ip, community, port) do
      {:ok, modems} ->
        case Enum.find(modems, fn m -> String.downcase(m.mac) == String.downcase(mac_address) end) do
          nil -> {:error, :not_found}
          modem -> {:ok, modem}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Convert uptime in hundredths of seconds to a human-readable string.
  """
  @spec format_uptime(integer()) :: String.t()
  def format_uptime(hundredths) when is_integer(hundredths) do
    seconds = div(hundredths, 100)
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    seconds = rem(seconds, 60)

    parts = []
    parts = if days > 0, do: ["#{days} day#{plural(days)}" | parts], else: parts
    parts = if hours > 0, do: ["#{hours} hour#{plural(hours)}" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes} minute#{plural(minutes)}" | parts], else: parts

    parts = if length(parts) > 0 do
      ["#{seconds} second#{plural(seconds)}" | parts]
    else
      if seconds > 0 or parts == [] do
        ["#{seconds} second#{plural(seconds)}" | parts]
      else
        parts
      end
    end

    parts = if parts == [], do: ["0 seconds"], else: parts

    parts |> Enum.reverse() |> Enum.join(", ")
  end

  @spec plural(integer()) :: String.t()
  defp plural(1), do: ""
  defp plural(_), do: "s"
end
