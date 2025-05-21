defmodule FirmwareManager.ModemSNMP do
  @moduledoc """
  Provides SNMP functionality for interacting with cable modems using the snmp_ex library.
  """

  alias SNMP

  # Common OIDs for cable modems
  @sys_descr [1, 3, 6, 1, 2, 1, 1, 1, 0]
  @sys_name [1, 3, 6, 1, 2, 1, 1, 5, 0]
  @sys_contact [1, 3, 6, 1, 2, 1, 1, 4, 0]
  @sys_location [1, 3, 6, 1, 2, 1, 1, 6, 0]
  @sys_uptime [1, 3, 6, 1, 2, 1, 1, 3, 0]

  # DOCSIS OIDs
  @docs_if_docs_dev_sw_admin_status [1, 3, 6, 1, 2, 1, 69, 1, 3, 1, 0]
  @docs_if_docs_dev_sw_oper_status [1, 3, 6, 1, 2, 1, 69, 1, 3, 2, 0]
  @docs_if_docs_dev_sw_server [1, 3, 6, 1, 2, 1, 69, 1, 3, 3, 0]
  @docs_if_docs_dev_sw_filename [1, 3, 6, 1, 2, 1, 69, 1, 3, 4, 0]
  @docs_if_sw_version [1, 3, 6, 1, 4, 1, 4491, 2, 1, 20, 1, 2, 0]
  @docs_if_docs_dev_sw_admin_status_upgrade 3
  @docs_dev_sw_server_address_type [1, 3, 6, 1, 2, 1, 69, 1, 4, 1, 0]
  @docs_dev_sw_server_address [1, 3, 6, 1, 2, 1, 69, 1, 4, 2, 0]
  @docs_dev_sw_server_boot_filename [1, 3, 6, 1, 2, 1, 69, 1, 4, 3, 0]

  @doc """
  Check if SNMP-based firmware upgrades are allowed on the modem.

  ## Parameters

    * `ip` - IP address of the modem
    * `community` - SNMP read community string
    * `port` - SNMP port (default: 161)

  ## Returns

    * `{:ok, map()}` - Map containing upgrade capability information
    * `{:error, reason}` - If the operation fails
  """
  def check_upgrade_capability(ip, community, port \\ 1161) do
    credential = SNMP.credential(%{version: :v2, community: community})
    uri = URI.parse("snmp://#{ip}:#{port}")

    varbinds = [
      %{oid: @docs_if_docs_dev_sw_admin_status},
      %{oid: @docs_dev_sw_server_address_type},
      %{oid: @docs_dev_sw_server_address},
      %{oid: @docs_dev_sw_server_boot_filename}
    ]

    case SNMP.request(%{uri: uri, credential: credential, varbinds: varbinds}) do
      {:ok, [
        %{value: admin_status},
        %{value: server_addr_type},
        %{value: server_addr},
        %{value: boot_filename}
      ]} ->
        upgrade_allowed = admin_status == @docs_if_docs_dev_sw_admin_status_upgrade

        {:ok, %{
          upgrade_allowed: upgrade_allowed,
          admin_status: admin_status,
          server_addr_type: server_addr_type,
          server_addr: server_addr,
          boot_filename: boot_filename
        }}

      error ->
        error
    end
  end

  def get_modem_info(ip, community, port \\ 1161) when is_binary(ip) and is_binary(community) do
    credential = SNMP.credential(%{version: :v2, community: community})
    uri = URI.parse("snmp://#{ip}:#{port}")

    # Get basic system info
    varbinds = [
      %{oid: @sys_descr},
      %{oid: @sys_name},
      %{oid: @sys_contact},
      %{oid: @sys_location},
      %{oid: @sys_uptime},
      %{oid: @docs_if_sw_version}
    ]

    with {:ok, [
      %{value: sys_descr},
      %{value: sys_name},
      %{value: sys_contact},
      %{value: sys_location},
      %{value: sys_uptime},
      %{value: docsis_version}
    ]} <- SNMP.request(%{uri: uri, credential: credential, varbinds: varbinds}),

         # Check upgrade capability
         {:ok, upgrade_info} <- check_upgrade_capability(ip, community, port) do

      {:ok, %{
        system_description: sys_descr,
        system_name: sys_name,
        system_contact: sys_contact,
        system_location: sys_location,
        system_uptime: sys_uptime,
        docsis_version: if(is_binary(docsis_version), do: docsis_version, else: "Unknown"),
        upgrade_capability: upgrade_info
      }}
    else
      error -> error
    end
  end

  @doc """
  Upgrade modem firmware using SNMP.

  ## Parameters

    * `ip` - IP address of the modem
    * `write_community` - SNMP write community string
    * `tftp_server` - IP address of the TFTP server
    * `firmware_file` - Filename of the firmware on the TFTP server
    * `port` - SNMP port (default: 161)

  ## Returns

    * `:ok` - If the upgrade command was sent successfully
    * `{:error, reason}` - If the operation fails
  """
  def upgrade_firmware(ip, write_community, tftp_server, firmware_file, port \\ 1161)
      when is_binary(ip) and is_binary(write_community) and
           is_binary(tftp_server) and is_binary(firmware_file) do
    credential = SNMP.credential(%{version: :v2, community: write_community})
    uri = URI.parse("snmp://#{ip}:#{port}")

    # First verify upgrade is allowed
    case check_upgrade_capability(ip, write_community, port) do
      {:ok, %{upgrade_allowed: true}} ->
        # Set TFTP server
        case SNMP.request(%{
          uri: uri,
          credential: credential,
          varbinds: [
            %{
              oid: @docs_if_docs_dev_sw_server,
              type: :octet_string,
              value: tftp_server
            },
            %{
              oid: @docs_if_docs_dev_sw_filename,
              type: :octet_string,
              value: firmware_file
            },
            %{
              oid: @docs_if_docs_dev_sw_admin_status,
              type: :integer,
              value: @docs_if_docs_dev_sw_admin_status_upgrade
            }
          ]
        }) do
          {:ok, _response} ->
            # Verify the upgrade started
            case get_upgrade_status(ip, write_community, port) do
              {:ok, :upgrade_from_mgt_sw} -> :ok
              error -> error
            end

          error ->
            error
        end

      {:ok, %{upgrade_allowed: false}} ->
        {:error, :upgrade_not_allowed}

      error ->
        error
    end
  end

  @doc """
  Get the current firmware upgrade status of the modem.

  ## Parameters

    * `ip` - IP address of the modem
    * `community` - SNMP read community string
    * `port` - SNMP port (default: 161)

  ## Returns

    * `{:ok, status}` - Current upgrade status as an atom
    * `{:error, reason}` - If the operation fails
  """
  def get_upgrade_status(ip, community, port \\ 1161) do
    credential = SNMP.credential(%{version: :v2, community: community})
    uri = URI.parse("snmp://#{ip}:#{port}")

    case SNMP.request(%{
      uri: uri,
      credential: credential,
      varbinds: [%{oid: @docs_if_docs_dev_sw_oper_status}]
    }) do
      {:ok, [%{value: status}]} ->
        {:ok, status_code_to_atom(status)}
      error ->
        error
    end
  end

  defp status_code_to_atom(1), do: :upgrade_from_mgt_sw
  defp status_code_to_atom(2), do: :upgrade_from_sw_repo
  defp status_code_to_atom(3), do: :provisioning_restart
  defp status_code_to_atom(4), do: :upgrade_complete
  defp status_code_to_atom(5), do: :checking_name
  defp status_code_to_atom(6), do: :acp_restart
  defp status_code_to_atom(7), do: :wait_dhcp
  defp status_code_to_atom(8), do: :wait_ranging
  defp status_code_to_atom(9), do: :upgrade_failed
  defp status_code_to_atom(_), do: :unknown
end
