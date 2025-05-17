defmodule FirmwareManager.CMTS.SNMP do
  @moduledoc """
  Module for interacting with Cable Modem Termination System (CMTS) devices via SNMP.
  """
  require Logger
  alias SNMP

  # DOCS-IF-MIB OIDs for CMTS
  @docs_if_mib [1, 3, 6, 1, 2, 1, 10, 127, 1, 3, 3, 1]  # docsIfCmtsCmStatusTable

  # Table columns
  @cmts_cm_status_index        @docs_if_mib ++ [1]  # docsIfCmtsCmStatusIndex
  @cmts_cm_status_mac_address  @docs_if_mib ++ [2]  # docsIfCmtsCmStatusMacAddress
  @cmts_cm_status_ip_address   @docs_if_mib ++ [4]  # docsIfCmtsCmStatusInetAddress
  @cmts_cm_status_value        @docs_if_mib ++ [6]  # docsIfCmtsCmStatusValue
  @cmts_cm_status_uptime       @docs_if_mib ++ [7]  # docsIfCmtsCmStatusOnlineTime

  # Status values
  @cm_status_online 8
  @cm_status_offline 9

  @doc """
  Discover all modems connected to the CMTS.

  ## Parameters
    * `ip` - IP address of the CMTS
    * `community` - SNMP community string (read-only)
    * `port` - SNMP port (default: 161)
    * `timeout` - SNMP timeout in milliseconds (default: 5000)
    * `retries` - Number of SNMP retries (default: 2)

  ## Returns
    * `{:ok, [%{mac: String.t, ip: String.t, status: atom, uptime: integer}]}` - List of modems
    * `{:error, reason}` - If the operation fails
  """
  @spec discover_modems(String.t, String.t, :inet.port_number, integer, integer) ::
        {:ok, [map]} | {:error, any}
  def discover_modems(ip, community, port \\ 161, timeout \\ 5000, retries \\ 2) do
    credential = SNMP.credential(%{version: :v2c, community: community, timeout: timeout, retries: retries})
    uri = URI.parse("snmp://#{ip}:#{port}")

    # Get all modem entries from the CMTS
    varbinds = [
      %{oid: @cmts_cm_status_index},
      %{oid: @cmts_cm_status_mac_address},
      %{oid: @cmts_cm_status_ip_address},
      %{oid: @cmts_cm_status_value},
      %{oid: @cmts_cm_status_uptime}
    ]

    case SNMP.request(%{uri: uri, credential: credential, varbinds: varbinds}) do
      {:ok, [indices, macs, ips, statuses, uptimes]} ->
        process_modems(indices, macs, ips, statuses, uptimes)
      error ->
        Logger.error("Failed to discover modems: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get details for a specific modem by its MAC address.

  ## Parameters
    * `ip` - IP address of the CMTS
    * `community` - SNMP community string (read-only)
    * `mac` - MAC address of the modem (format: "00:11:22:33:44:55")
    * `port` - SNMP port (default: 161)

  ## Returns
    * `{:ok, %{mac: String.t, ip: String.t, status: atom, uptime: integer}}` - Modem details
    * `{:error, :not_found}` - If modem is not found
    * `{:error, reason}` - If the operation fails
  """
  @spec get_modem(String.t, String.t, String.t, :inet.port_number) ::
        {:ok, map} | {:error, atom | any}
  def get_modem(ip, community, mac, port \\ 161) do
    case discover_modems(ip, community, port) do
      {:ok, modems} ->
        case Enum.find(modems, &(&1.mac == format_mac(mac))) do
          nil -> {:error, :not_found}
          modem -> {:ok, modem}
        end
      error ->
        error
    end
  end

  # Private functions

  defp process_modems(indices, macs, ips, statuses, uptimes) do
    # Pair up the values by index
    modems = Enum.zip_with([indices, macs, ips, statuses, uptimes], fn
      [%{value: _index}, %{value: mac}, %{value: ip}, %{value: status}, %{value: uptime} | _] ->
        %{
          mac: format_mac(mac),
          ip: format_ip(ip),
          status: status_to_atom(status),
          uptime: uptime
        }
      _ ->
        nil
    end)

    {:ok, Enum.reject(modems, &is_nil/1)}
  end

  defp format_mac(mac) when is_binary(mac) do
    mac
    |> String.replace(~r/[^0-9a-fA-F]/, "")
    |> String.downcase()
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(":")
  end

  defp format_mac(mac) when is_list(mac) do
    mac
    |> Enum.map(&Integer.to_string(&1, 16) |> String.pad_leading(2, "0"))
    |> Enum.join(":")
    |> String.downcase()
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip |> Tuple.to_list() |> Enum.join(".")
  end

  defp format_ip(ip) when is_binary(ip) do
    ip
  end

  defp status_to_atom(@cm_status_online), do: :online
  defp status_to_atom(@cm_status_offline), do: :offline
  defp status_to_atom(_), do: :unknown

  @doc """
  Convert uptime in hundredths of seconds to a human-readable string.
  """
  @spec format_uptime(integer) :: String.t
  def format_uptime(hundredths) when is_integer(hundredths) and hundredths >= 0 do
    seconds = div(hundredths, 100)

    days = div(seconds, 86_400)
    seconds_remaining = rem(seconds, 86_400)

    hours = div(seconds_remaining, 3_600)
    seconds_remaining = rem(seconds_remaining, 3_600)

    minutes = div(seconds_remaining, 60)
    seconds_remaining = rem(seconds_remaining, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{seconds_remaining}s"
      true -> "#{seconds_remaining}s"
    end
  end

  def format_uptime(_), do: "unknown"
end
