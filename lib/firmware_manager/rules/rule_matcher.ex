defmodule FirmwareManager.Rules.RuleMatcher do
  @moduledoc """
  Build upgrade plans by filtering modems using MAC CIDR/mask rules and sysDescr glob patterns.

  - MAC rules: FirmwareManager.MacCIDR (e.g., "aa:bb:cc:00:00:00/24")
  - sysDescr glob: uses % as wildcard (SQL LIKE style). Case-insensitive by default.
  """

  alias FirmwareManager.MacCIDR
  alias FirmwareManager.CMTSSNMP
  alias FirmwareManager.ModemSNMP
  alias FirmwareManager.SNMP.Simulator
  alias FirmwareManager.Settings
  alias FirmwareManager.Modem

  require Logger

  @type plan_opts :: %{
          optional(:mac_rule) => String.t(),
          optional(:sysdescr_glob) => String.t(),
          optional(:tftp_server) => String.t(),
          optional(:force?) => boolean(),
          required(:firmware_file) => String.t()
        }

  @doc """
  Convert a simple % glob to a regex. Case-insensitive.
  """
  @spec glob_to_regex(String.t()) :: Regex.t()
  def glob_to_regex(glob) when is_binary(glob) do
    escaped = Regex.escape(glob)
    pattern = String.replace(escaped, "%", ".*")
    Regex.compile!("^" <> pattern <> "$", "i")
  end

  @doc """
  SQL-like case-insensitive match using % wildcard.
  """
  @spec like?(String.t(), String.t()) :: boolean()
  def like?(string, glob) when is_binary(string) and is_binary(glob) do
    Regex.match?(glob_to_regex(glob), string)
  end

  @doc """
  Discover modems from a CMTS and build an upgrade plan by applying filters.

  Returns {:ok, [%{mac, ip, port, sysdescr, tftp_server, firmware_file}]} or {:error, reason}.
  """
  @spec plan_upgrades(map(), plan_opts()) :: {:ok, [map()]} | {:error, any()}
  def plan_upgrades(%{ip: cmts_ip} = cmts, %{firmware_file: fw_file} = opts) when is_binary(fw_file) do
    t = "#{cmts_ip}:#{cmts.snmp_port || 161}"
    read_comm = cmts.modem_snmp_read || cmts.snmp_read || "public"

    with {:ok, mods} <- CMTSSNMP.discover_modems(cmts_ip, read_comm, cmts.snmp_port || 161) do
      mods = if cmts.virtual, do: Simulator.enrich_with_sim_ports(cmts, mods), else: mods

      mac_rule = Map.get(opts, :mac_rule)
      sys_glob = Map.get(opts, :sysdescr_glob)
      tftp = Map.get(opts, :tftp_server) || Settings.tftp_server()

      plan =
        mods
        |> maybe_filter_mac(mac_rule)
        |> Enum.map(fn m ->
          port = Map.get(m, :port) || 161
          # For simulated per-modem ports, use write community as device community
          comm = if cmts.virtual and port != 161, do: cmts.modem_snmp_write || read_comm, else: read_comm
          case ModemSNMP.get_modem_info(m.ip, comm, port) do
            {:ok, info} -> Map.merge(m, %{sysdescr: to_string(info.system_description), port: port})
            _ -> Map.merge(m, %{sysdescr: "", port: port})
          end
        end)
        |> maybe_filter_sysdescr(sys_glob)
        |> Enum.map(fn m ->
          %{
            mac: m.mac,
            ip: m.ip,
            port: m.port || 161,
            sysdescr: m.sysdescr,
            tftp_server: tftp,
            firmware_file: fw_file
          }
        end)
        |> maybe_filter_already_upgraded(Map.get(opts, :force?, false))

      {:ok, plan}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def plan_upgrades(_cmts, _opts), do: {:error, :missing_firmware_file}

  @doc """
  Build a combined upgrade plan across multiple CMTS entries.
  Each plan item is annotated with per-item read/write communities for execution.
  """
  @spec plan_upgrades_multi([map()], plan_opts()) :: {:ok, [map()]} | {:error, any()}
  def plan_upgrades_multi(cmts_list, opts) when is_list(cmts_list) do
    results =
      Enum.map(cmts_list, fn cmts ->
        case plan_upgrades(cmts, opts) do
          {:ok, items} ->
            items =
              Enum.map(items, fn it ->
                Map.merge(it, %{
                  read_comm: cmts.modem_snmp_read || cmts.snmp_read || "public",
                  write_comm: cmts.modem_snmp_write,
                  cmts_id: cmts.id
                })
              end)
            {:ok, items}

          {:error, reason} -> {:error, {cmts.id, reason}}
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        combined =
          results
          |> Enum.flat_map(fn {:ok, items} -> items end)
        {:ok, combined}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Apply an upgrade plan concurrently.

  Options:
    - :concurrency (default: min(8, System.schedulers_online()))
    - :poll_ms (default: 300)
    - :poll_attempts (default: 50)

  Returns {:ok, results} where results is a list of %{mac, result, final_status} or {:error, reason}.
  """
  @spec apply_plan(map(), [map()], keyword()) :: {:ok, [map()]} | {:error, any()}
  def apply_plan(%{} = _cmts, plan, opts \\ []) when is_list(plan) do
    # Dry-run: return the plan annotated, without executing
    if opts[:dry_run] do
      preview =
        Enum.map(plan, fn item ->
          Map.put(item, :result, :dry_run)
        end)

      {:ok, preview}
    else
      cmts = _cmts
      concurrency = opts[:concurrency] || min(8, System.schedulers_online())
      poll_ms = opts[:poll_ms] || 300
      poll_attempts = opts[:poll_attempts] || 50

      write_comm = cmts.modem_snmp_write
      read_comm = cmts.modem_snmp_read || cmts.snmp_read || "public"

      results =
        Task.async_stream(
          plan,
          fn item -> do_apply_item(item, write_comm, read_comm, poll_ms, poll_attempts) end,
          max_concurrency: concurrency,
          ordered: false,
          timeout: (poll_ms * poll_attempts) + 15_000
        )
        |> Enum.map(fn
          {:ok, res} -> res
          {:exit, reason} -> %{mac: Map.get(hd(plan), :mac), result: {:error, {:exit, reason}}}
          {:error, reason} -> %{mac: Map.get(hd(plan), :mac), result: {:error, reason}}
        end)

      {:ok, results}
    end
  end

  defp do_apply_item(%{mac: mac, ip: ip, port: port0, tftp_server: tftp, firmware_file: file} = _item, write_comm, read_comm, poll_ms, poll_attempts) do
    port = port0 || 161

    pre_sysdescr =
      case ModemSNMP.get_modem_info(ip, read_comm, port) do
        {:ok, %{system_description: d}} -> to_string(d)
        _ -> ""
      end

    # Trigger upgrade
    result = ModemSNMP.upgrade_firmware(ip, write_comm, tftp, file, port)

    case result do
      :ok -> :ok
      {:ok, _status} -> :ok
      {:error, reason} ->
        Logger.error("Upgrade trigger failed for #{mac} @ #{ip}:#{port}: #{inspect(reason)}")
        {:error, reason}
    end
    |> case do
      :ok ->
        final = poll_until_final(ip, read_comm, port, poll_ms, poll_attempts)
        case final do
          :upgrade_complete ->
            post_sysdescr =
              case ModemSNMP.get_modem_info(ip, read_comm, port) do
                {:ok, %{system_description: d}} -> to_string(d)
                _ -> pre_sysdescr
              end
            _ = Modem.create_upgrade_log(%{mac_address: mac, old_sysdescr: pre_sysdescr, new_sysdescr: post_sysdescr, new_firmware: to_string(file), rule_id: Map.get(_item, :rule_id)})
            %{mac: mac, result: :ok, final_status: final}

          other ->
            %{mac: mac, result: {:error, other}, final_status: other}
        end

      {:error, reason} -> %{mac: mac, result: {:error, reason}, final_status: :unknown}
    end
  end

  defp poll_until_final(ip, read_comm, port, poll_ms, poll_attempts) do
    Stream.repeatedly(fn ->
      Process.sleep(poll_ms)
      ModemSNMP.get_upgrade_status(ip, read_comm, port)
    end)
    |> Enum.take(poll_attempts)
    |> Enum.reduce_while(:unknown, fn
      {:ok, :upgrade_complete}, _ -> {:halt, :upgrade_complete}
      {:ok, :upgrade_failed}, _ -> {:halt, :upgrade_failed}
      {:ok, _}, acc -> {:cont, acc}
      _other, acc -> {:cont, acc}
    end)
  end

  defp maybe_filter_mac(mods, nil), do: mods
  defp maybe_filter_mac(mods, rule) when is_binary(rule) do
    Enum.filter(mods, fn m -> MacCIDR.mac_match?(m.mac, rule) end)
  end

  defp maybe_filter_sysdescr(mods, nil), do: mods
  defp maybe_filter_sysdescr(mods, glob) when is_binary(glob) do
    Enum.filter(mods, fn m -> like?(m.sysdescr || "", glob) end)
  end

  defp maybe_filter_already_upgraded(plan, true), do: plan
  defp maybe_filter_already_upgraded(plan, false) do
    Enum.reject(plan, fn %{mac: mac, firmware_file: file} ->
      FirmwareManager.Modem.upgrade_log_exists?(mac, to_string(file))
    end)
  end
  @doc """
  Apply a combined upgrade plan (from plan_upgrades_multi) using per-item credentials.
  """
  @spec apply_plan_multi([map()], keyword()) :: {:ok, [map()]}
  def apply_plan_multi(plan, opts \\ []) when is_list(plan) do
    concurrency = opts[:concurrency] || min(8, System.schedulers_online())
    poll_ms = opts[:poll_ms] || 300
    poll_attempts = opts[:poll_attempts] || 50

    if opts[:dry_run] do
      {:ok, Enum.map(plan, &Map.put(&1, :result, :dry_run))}
    else
      Task.async_stream(
        plan,
        fn %{mac: mac, ip: ip, port: port0, tftp_server: tftp, firmware_file: file, read_comm: read_comm, write_comm: write_comm} ->
          port = port0 || 161

          pre_sysdescr =
            case ModemSNMP.get_modem_info(ip, read_comm, port) do
              {:ok, %{system_description: d}} -> to_string(d)
              _ -> ""
            end

          res = ModemSNMP.upgrade_firmware(ip, write_comm, tftp, file, port)

          exec = case res do
            :ok -> :ok
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

          case exec do
            :ok ->
              final = poll_until_final(ip, read_comm, port, poll_ms, poll_attempts)
              case final do
                :upgrade_complete ->
                  post_sysdescr =
                    case ModemSNMP.get_modem_info(ip, read_comm, port) do
                      {:ok, %{system_description: d}} -> to_string(d)
                      _ -> pre_sysdescr
                    end
                  _ = Modem.create_upgrade_log(%{mac_address: mac, old_sysdescr: pre_sysdescr, new_sysdescr: post_sysdescr, new_firmware: to_string(file), rule_id: Map.get(%{mac: mac, ip: ip, port: port, tftp_server: tftp, firmware_file: file}, :rule_id)})
                  %{mac: mac, result: :ok, final_status: final}

                other -> %{mac: mac, result: {:error, other}, final_status: other}
              end

            {:error, reason} -> %{mac: mac, result: {:error, reason}, final_status: :unknown}
          end
        end,
        max_concurrency: concurrency,
        ordered: false,
        timeout: (poll_ms * poll_attempts) + 15_000
      )
      |> Enum.map(fn {:ok, v} -> v; other -> %{result: {:error, other}} end)
      |> then(&{:ok, &1})
    end
  end
end
