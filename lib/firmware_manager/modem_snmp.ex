defmodule FirmwareManager.ModemSNMP do
  @moduledoc """
  Provides SNMP functionality for interacting with cable modems using snmpkit.
  """

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

  defp target(ip, port), do: "#{ip}:#{port}"

  @doc """
  Check if SNMP-based firmware upgrades are allowed on the modem.

  Strategy:
  - Require docsIfDocsDevSwAdminStatus (1.3.6.1.2.1.69.1.3.1.0)
  - Optionally read server/filename using modern DOCS-IF (69.1.3.*) or legacy DOCS-DEVICE (69.1.4.*) as available
  - Consider upgrade allowed if admin status OID is present/readable
  """
  def check_upgrade_capability(ip, community, port \\ 161) do
    t = target(ip, port)
    opts = [community: community, version: :v2c]

    with {:ok, {_o1, _t1, admin_status}} <- SnmpKit.SnmpMgr.get_with_type(t, @docs_if_docs_dev_sw_admin_status, opts) do
      # Try modern/legacy variants, tolerate missing values
      server =
        case SnmpKit.SnmpMgr.get_with_type(t, @docs_if_docs_dev_sw_server, opts) do
          {:ok, {_o, _t, v}} -> v
          _ -> nil
        end

      filename =
        case SnmpKit.SnmpMgr.get_with_type(t, @docs_if_docs_dev_sw_filename, opts) do
          {:ok, {_o, _t, v}} -> v
          _ ->
            case SnmpKit.SnmpMgr.get_with_type(t, @docs_dev_sw_server_boot_filename, opts) do
              {:ok, {_o2, _t2, v2}} -> v2
              _ -> nil
            end
        end

      server_addr_type =
        case SnmpKit.SnmpMgr.get_with_type(t, @docs_dev_sw_server_address_type, opts) do
          {:ok, {_o, _t, v}} -> v
          _ -> nil
        end

      server_addr =
        case SnmpKit.SnmpMgr.get_with_type(t, @docs_dev_sw_server_address, opts) do
          {:ok, {_o, _t, v}} -> v
          _ -> nil
        end

      {:ok,
       %{
         upgrade_allowed: true,
         admin_status: admin_status,
         server_addr_type: server_addr_type,
         server_addr: server_addr,
         boot_filename: filename,
         server: server
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def get_modem_info(ip, community, port \\ 161) when is_binary(ip) and is_binary(community) do
    t = target(ip, port)

    with {:ok, {_o1, _t1, sys_descr}} <- SnmpKit.SnmpMgr.get_with_type(t, @sys_descr, community: community, version: :v2c),
         {:ok, {_o2, _t2, sys_name}} <- SnmpKit.SnmpMgr.get_with_type(t, @sys_name, community: community, version: :v2c),
         {:ok, {_o3, _t3, sys_contact}} <- SnmpKit.SnmpMgr.get_with_type(t, @sys_contact, community: community, version: :v2c),
         {:ok, {_o4, _t4, sys_location}} <- SnmpKit.SnmpMgr.get_with_type(t, @sys_location, community: community, version: :v2c),
         {:ok, {_o5, _t5, sys_uptime}} <- SnmpKit.SnmpMgr.get_with_type(t, @sys_uptime, community: community, version: :v2c),
         {:ok, {_o6, _t6, docsis_version}} <- SnmpKit.SnmpMgr.get_with_type(t, @docs_if_sw_version, community: community, version: :v2c),
         {:ok, upgrade_info} <- check_upgrade_capability(ip, community, port) do
      {:ok,
       %{
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
  """
  def upgrade_firmware(ip, write_community, tftp_server, firmware_file, port \\ 161)
      when is_binary(ip) and is_binary(write_community) and
           is_binary(tftp_server) and is_binary(firmware_file) do
    t = target(ip, port)

    case check_upgrade_capability(ip, write_community, port) do
      {:ok, %{upgrade_allowed: true}} ->
        # Perform three SETs in sequence; snmpkit set returns {:ok, value} or {:error, reason}
        with {:ok, _} <- SnmpKit.SnmpMgr.set(t, @docs_if_docs_dev_sw_server, tftp_server, community: write_community, version: :v2c),
             {:ok, _} <- SnmpKit.SnmpMgr.set(t, @docs_if_docs_dev_sw_filename, firmware_file, community: write_community, version: :v2c),
             {:ok, _} <- SnmpKit.SnmpMgr.set(t, @docs_if_docs_dev_sw_admin_status, @docs_if_docs_dev_sw_admin_status_upgrade, community: write_community, version: :v2c) do
          case get_upgrade_status(ip, write_community, port) do
            {:ok, :upgrade_from_mgt_sw} -> :ok
            other -> other
          end
        else
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{upgrade_allowed: false}} ->
        {:error, :upgrade_not_allowed}

      error ->
        error
    end
  end

  @doc """
  Get the current firmware upgrade status of the modem.
  """
  def get_upgrade_status(ip, community, port \\ 161) do
    t = target(ip, port)

    case SnmpKit.SnmpMgr.get_with_type(t, @docs_if_docs_dev_sw_oper_status, community: community, version: :v2c) do
      {:ok, {_oid, _type, status}} -> {:ok, status_code_to_atom(status)}
      error -> error
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
