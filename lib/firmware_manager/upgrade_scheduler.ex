defmodule FirmwareManager.UpgradeScheduler do
  @moduledoc """
  Periodically runs all enabled upgrade rules in the background and logs results.

  Options: [interval_ms: 300_000]
  """
  use GenServer
  alias FirmwareManager.Modem
  alias FirmwareManager.Rules.RuleMatcher
  alias FirmwareManager.UpgradeAPI

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, 300_000)
    schedule_tick(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    # Run all enabled rules
    run_all_enabled()
    schedule_tick(interval)
    {:noreply, state}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end

  def run_all_enabled do
    # Fetch enabled rules and apply each
    rules = UpgradeAPI.list_enabled_rules()
    cmts_list = Modem.list_cmts()

    Enum.each(rules, fn rule ->
      opts =
        %{}
        |> Map.put(:firmware_file, rule.firmware_file)
        |> then(fn acc ->
          if rule.mac_rule && rule.mac_rule != "",
            do: Map.put(acc, :mac_rule, rule.mac_rule),
            else: acc
        end)
        |> then(fn acc ->
          if rule.sysdescr_glob && rule.sysdescr_glob != "",
            do: Map.put(acc, :sysdescr_glob, rule.sysdescr_glob),
            else: acc
        end)
        |> then(fn acc ->
          if rule.tftp_server && rule.tftp_server != "",
            do: Map.put(acc, :tftp_server, rule.tftp_server),
            else: acc
        end)

      with {:ok, plan0} <- RuleMatcher.plan_upgrades_multi(cmts_list, opts),
           plan <- Enum.map(plan0, &Map.put(&1, :rule_id, rule.id)),
           {:ok, _results} <-
             RuleMatcher.apply_plan_multi(plan, concurrency: 6, poll_ms: 300, poll_attempts: 50) do
        :ok
      else
        _ -> :ok
      end
    end)

    :ok
  end
end
