defmodule FirmwareManagerWeb.CmtsLive.Show do
  use FirmwareManagerWeb, :live_view

  alias FirmwareManager.Modem
  alias FirmwareManager.SNMP.Simulator
  alias FirmwareManager.CMTSSNMP
  alias FirmwareManager.ModemSNMP
  alias FirmwareManager.Rules.RuleMatcher
  alias FirmwareManager.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:discovered_modems, [])
     |> assign(:discovery_error, nil)
     |> assign(:upgrade_modal, false)
     |> assign(:upgrade_error, nil)
     |> assign(:upgrade_target, nil)
     |> assign(:rule_mac, "")
     |> assign(:rule_glob, "")
     |> assign(:rule_firmware, "")
     |> assign(:rule_tftp, Settings.tftp_server())
     |> assign(:upgrade_plan_preview, [])
     |> assign(:upgrade_plan_error, nil)
     |> assign(:upgrade_run_results, [])}
  end

  @impl true
  def handle_params(%{"id" => id, "discover" => "1"}, _, socket) do
    cmts = Modem.get_cmts!(id)
    _ = if cmts.virtual, do: Simulator.ensure_cmts_sim(cmts), else: :noop
    port = cmts.snmp_port || 161

    case CMTSSNMP.discover_modems(cmts.ip, cmts.modem_snmp_read, port) do
      {:ok, modems} ->
        modems = Simulator.enrich_with_sim_ports(cmts, modems)
        modems = enrich_with_sysdescr(cmts, modems)
        {:noreply,
         socket
         |> assign(:page_title, "CMTS Details")
         |> assign(:cmts, cmts)
         |> assign(:discovered_modems, modems)
         |> assign(:discovery_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:page_title, "CMTS Details")
         |> assign(:cmts, cmts)
         |> assign(:discovered_modems, [])
         |> assign(:discovery_error, inspect(reason))}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "CMTS Details")
     |> assign(:cmts, Modem.get_cmts!(id))}
  end

  @impl true
  def handle_event("open_upgrade_modal", %{"mac" => mac, "ip" => ip, "port" => port_str}, %{assigns: %{cmts: _cmts}} = socket) do
    port = case port_str do
      nil -> nil
      "" -> nil
      v when is_binary(v) -> case Integer.parse(v) do {i,_} -> i; :error -> nil end
      v when is_integer(v) -> v
      _ -> nil
    end

    {:noreply,
     socket
     |> assign(:upgrade_modal, true)
     |> assign(:upgrade_error, nil)
     |> assign(:upgrade_target, %{mac: mac, ip: ip, port: port})}
  end

  @impl true
  def handle_event("cancel_upgrade", _params, socket) do
    {:noreply, assign(socket, upgrade_modal: false, upgrade_error: nil, upgrade_target: nil)}
  end

  @impl true
  def handle_event("perform_spot_upgrade", %{"tftp_server" => tftp, "firmware_file" => file}, %{assigns: %{cmts: cmts, upgrade_target: target}} = socket) do
    ip = target.ip
    port = target.port || 161
    write_comm = cmts.modem_snmp_write
    read_comm = cmts.modem_snmp_read

    # Capture pre-upgrade sysDescr for logging
    pre_sysdescr =
      case ModemSNMP.get_modem_info(ip, read_comm, port) do
        {:ok, %{system_description: d}} -> to_string(d)
        _ -> ""
      end

    case ModemSNMP.upgrade_firmware(ip, write_comm, tftp, file, port) do
      :ok ->
        # Poll in background and write log on completion
        Task.start(fn -> poll_and_log_upgrade(target.mac, ip, port, read_comm, file, pre_sysdescr) end)
        {:noreply,
         socket
         |> put_flash(:info, "Upgrade triggered for #{target.mac} (#{ip}:#{port}).")
         |> assign(:upgrade_modal, false)
         |> assign(:upgrade_error, nil)
         |> assign(:upgrade_target, nil)}

      {:ok, status} ->
        Task.start(fn -> poll_and_log_upgrade(target.mac, ip, port, read_comm, file, pre_sysdescr) end)
        {:noreply,
         socket
         |> put_flash(:info, "Upgrade triggered for #{target.mac} (#{ip}:#{port}); status: #{status}.")
         |> assign(:upgrade_modal, false)
         |> assign(:upgrade_error, nil)
         |> assign(:upgrade_target, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, upgrade_error: inspect(reason))}
    end
  end



  @impl true
  def handle_event("preview_upgrade_plan", params, %{assigns: %{cmts: cmts}} = socket) do
    mac_rule = Map.get(params, "mac_rule", "")
    sys_glob = Map.get(params, "sysdescr_glob", "")
    fw_file = Map.get(params, "firmware_file", "")
    tftp = Map.get(params, "tftp_server", "")

    if fw_file == "" do
      {:noreply, assign(socket, upgrade_plan_error: "Firmware file is required", upgrade_plan_preview: [])}
    else
      opts = %{
        firmware_file: fw_file
      }
      opts = if mac_rule != "", do: Map.put(opts, :mac_rule, mac_rule), else: opts
      opts = if sys_glob != "", do: Map.put(opts, :sysdescr_glob, sys_glob), else: opts
      opts = if tftp != "", do: Map.put(opts, :tftp_server, tftp), else: opts

      case RuleMatcher.plan_upgrades(cmts, opts) do
        {:ok, plan} ->
          {:noreply,
           socket
           |> assign(:rule_mac, mac_rule)
           |> assign(:rule_glob, sys_glob)
           |> assign(:rule_firmware, fw_file)
           |> assign(:rule_tftp, if(tftp == "", do: Settings.tftp_server(), else: tftp))
           |> assign(:upgrade_plan_error, nil)
           |> assign(:upgrade_plan_preview, plan)
           |> assign(:upgrade_run_results, [])}

        {:error, reason} ->
          {:noreply, assign(socket, upgrade_plan_error: inspect(reason), upgrade_plan_preview: [], upgrade_run_results: [])}
      end
    end
  end

  @impl true
  def handle_event("run_upgrade_plan", _params, %{assigns: %{cmts: cmts, upgrade_plan_preview: plan}} = socket) do
    case RuleMatcher.apply_plan(cmts, plan, concurrency: 4, poll_ms: 300, poll_attempts: 50) do
      {:ok, results} ->
        {:noreply, assign(socket, upgrade_run_results: results) |> put_flash(:info, "Upgrade plan executing; results updated.")}
      other ->
        {:noreply, assign(socket, upgrade_plan_error: inspect(other))}
    end
  end

  @impl true
  def handle_event("discover_modems", _params, %{assigns: %{cmts: cmts}} = socket) do
    # If virtual, ensure simulator is running on snmp_port
    _ = if cmts.virtual, do: Simulator.ensure_cmts_sim(cmts), else: :noop

    port = cmts.snmp_port || 161

    case CMTSSNMP.discover_modems(cmts.ip, cmts.modem_snmp_read, port) do
      {:ok, modems} ->
        modems = Simulator.enrich_with_sim_ports(cmts, modems)
        modems = enrich_with_sysdescr(cmts, modems)
        {:noreply, assign(socket, discovered_modems: modems, discovery_error: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket, discovered_modems: [], discovery_error: inspect(reason))}
    end
  end
  defp poll_and_log_upgrade(mac, ip, port, read_comm, firmware_file, pre_sysdescr) do
    # Poll oper status up to ~15 seconds
    final =
      Stream.repeatedly(fn ->
        Process.sleep(300)
        ModemSNMP.get_upgrade_status(ip, read_comm, port)
      end)
      |> Enum.take(50)
      |> Enum.reduce_while(:unknown, fn
        {:ok, :upgrade_complete}, _ -> {:halt, :upgrade_complete}
        {:ok, :upgrade_failed}, _ -> {:halt, :upgrade_failed}
        {:ok, _phase}, acc -> {:cont, acc}
        _other, acc -> {:cont, acc}
      end)

    case final do
      :upgrade_complete ->
        # Fetch post-upgrade sysDescr
        new_sysdescr =
          case ModemSNMP.get_modem_info(ip, read_comm, port) do
            {:ok, %{system_description: d}} -> to_string(d)
            _ -> pre_sysdescr
          end
        _ = FirmwareManager.Modem.create_upgrade_log(%{
          mac_address: mac,
          old_sysdescr: pre_sysdescr,
          new_sysdescr: new_sysdescr,
          new_firmware: to_string(firmware_file)
        })
        :ok

      _ -> :noop
    end
  end

  defp enrich_with_sysdescr(cmts, modems) when is_list(modems) do
    read_comm = cmts.modem_snmp_read || cmts.snmp_read || "public"
    write_comm = cmts.modem_snmp_write || read_comm
    sim_sys = if cmts.virtual, do: FirmwareManager.SNMP.Simulator.modem_sysdescrs(cmts), else: %{}
    Enum.map(modems, fn m ->
      port = Map.get(m, :port) || 161
      comm = if cmts.virtual and port != 161, do: write_comm, else: read_comm
      sys =
        if cmts.virtual do
          case Map.fetch(sim_sys, String.downcase(m.mac)) do
            {:ok, v} -> v
            :error ->
              case FirmwareManager.ModemSNMP.get_modem_info(m.ip, comm, port) do
                {:ok, %{system_description: d}} -> to_string(d)
                _ -> ""
              end
          end
        else
          case FirmwareManager.ModemSNMP.get_modem_info(m.ip, comm, port) do
            {:ok, %{system_description: d}} -> to_string(d)
            _ -> ""
          end
        end
      Map.put(m, :sysdescr, sys)
    end)
  end
end
