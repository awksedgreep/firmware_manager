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
    # Set up SNMP credential and URI
    credential = SNMP.credential(%{version: :v2, community: community})
    uri = URI.parse("snmp://#{ip}:#{port}")

    # Only walk the columns we need: MAC addresses, status values, and IP addresses
    with {:ok, mac_addresses} <- walk_column(uri, credential, @docs_if_cmts_cm_status_mac_address),
         {:ok, status_values} <- walk_column(uri, credential, @docs_if_cmts_cm_status_value),
         {:ok, ip_addresses} <- walk_column(uri, credential, @docs_if_cmts_cm_status_inet_address) do
      # Combine the results by index
      modems = combine_column_data(mac_addresses, status_values, ip_addresses)
      {:ok, modems}
    else
      {:error, reason} -> 
        Logger.error("SNMP walk failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Walks a specific column in the CMTS status table.
  @spec walk_column(URI.t(), map(), list()) :: {:ok, map()} | {:error, any()}
  defp walk_column(uri, credential, column_oid) do
    try do
      # Perform the SNMP bulkwalk for this column
      stream = SNMP.bulkwalk(%{uri: uri, credential: credential, varbinds: [%{oid: column_oid}]})
      rows = Enum.to_list(stream)
      
      if is_list(rows) and rows != [] do
        # Extract index and value from each row
        result = Enum.reduce(rows, %{}, fn %{oid: oid, value: value}, acc ->
          # Extract the index from the OID (last element)
          index = List.last(oid)
          Map.put(acc, index, value)
        end)
        {:ok, result}
      else
        Logger.warning("No results for column #{inspect(column_oid)}")
        {:ok, %{}}
      end
    rescue
      e -> 
        Logger.error("Error walking column #{inspect(column_oid)}: #{inspect(e)}")
        {:error, e}
    end
  end

  # Combines data from multiple column walks into a list of modem maps.
  @spec combine_column_data(map(), map(), map()) :: [modem()]
  defp combine_column_data(mac_addresses, status_values, ip_addresses) do
    # Get all unique indices
    all_indices = mac_addresses |> Map.keys() |> MapSet.new()
    
    # Convert to list of modem maps
    Enum.map(all_indices, fn index ->
      # Extract MAC address
      mac = case Map.get(mac_addresses, index) do
        bin when is_binary(bin) ->
          try do
            # Convert binary MAC to colon-separated hex format
            bin
            |> :binary.bin_to_list()
            |> Enum.map(&Integer.to_string(&1, 16) |> String.pad_leading(2, "0"))
            |> Enum.join(":")
          rescue
            e ->
              Logger.error("Error parsing MAC address: #{inspect(bin)}, error: #{inspect(e)}")
              "00:00:00:00:00:00"
          end
        other -> 
          Logger.warning("Unexpected MAC address format: #{inspect(other)}")
          "unknown"
      end

      # Extract IP address
      ip = case Map.get(ip_addresses, index) do
        bin when is_binary(bin) and byte_size(bin) == 4 ->
          try do
            # Convert 4-byte binary IP to dotted decimal format
            bin
            |> :binary.bin_to_list()
            |> Enum.join(".")
          rescue
            e ->
              Logger.error("Error parsing IP address: #{inspect(bin)}, error: #{inspect(e)}")
              "0.0.0.0"
          end
        other -> 
          Logger.warning("Unexpected IP address format: #{inspect(other)}")
          "0.0.0.0"
      end

      # Extract status
      status_val = Map.get(status_values, index, 0)
      status = Map.get(@status_codes, status_val, :unknown)

      # Return the modem map
      %{mac: mac, ip: ip, status: status}
    end)
  end

  @doc """
  Gets information about a specific modem by MAC address.

  ## Parameters
    - `ip`: The IP address of the CMTS
    - `community`: SNMP community string (default: "public")
    - `mac_address`: The MAC address of the modem to find
    - `port`: SNMP port (default: 161)

  ## Returns
    - `{:ok, modem()}` if the modem is found
    - `{:error, :not_found}` if the modem is not found
    - `{:error, reason}` on other errors
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
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convert uptime in hundredths of seconds to a human-readable string.

  ## Examples
      iex> FirmwareManager.CMTSSNMP.format_uptime(0)
      "0 seconds"

      iex> FirmwareManager.CMTSSNMP.format_uptime(100)
      "1 second"

      iex> FirmwareManager.CMTSSNMP.format_uptime(6000)
      "1 minute, 0 seconds"

      iex> FirmwareManager.CMTSSNMP.format_uptime(366100)
      "1 hour, 1 minute, 1 second"
  """
  @spec format_uptime(integer()) :: String.t()
  def format_uptime(hundredths) when is_integer(hundredths) do
    seconds = div(hundredths, 100)
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    seconds = rem(seconds, 60)

    parts = []

    # Add each time part if greater than 0
    parts = if days > 0, do: ["#{days} day#{plural(days)}" | parts], else: parts
    parts = if hours > 0, do: ["#{hours} hour#{plural(hours)}" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes} minute#{plural(minutes)}" | parts], else: parts

    # Always show seconds if we have minutes or hours
    parts = if length(parts) > 0 do
      ["#{seconds} second#{plural(seconds)}" | parts]
    else
      # Only show seconds if they're non-zero or it's the only part
      if seconds > 0 or parts == [] do
        ["#{seconds} second#{plural(seconds)}" | parts]
      else
        parts
      end
    end

    # If still empty, it means everything was 0
    parts = if parts == [], do: ["0 seconds"], else: parts

    parts
    |> Enum.reverse()
    |> Enum.join(", ")
  end

  # Helper function to handle pluralization
  @spec plural(integer()) :: String.t()
  defp plural(1), do: ""
  defp plural(_), do: "s"
end
