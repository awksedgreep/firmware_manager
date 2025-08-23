defmodule FirmwareManager.UpgradeBoot do
  @moduledoc """
  Optional boot hook to start/stop the upgrade scheduler under a DynamicSupervisor.

  Controlled via application env:
    config :firmware_manager,
      upgrade_scheduler_enabled: true,
      upgrade_interval_ms: 300_000
  """
  use GenServer

  @impl true
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Start if enabled at boot
    if enabled?(), do: ensure_started()
    {:ok, state}
  end

  @doc "Enable and start the scheduler dynamically"
  def enable do
    Application.put_env(:firmware_manager, :upgrade_scheduler_enabled, true)
    ensure_started()
  end

  @doc "Disable and stop the scheduler dynamically"
  def disable do
    Application.put_env(:firmware_manager, :upgrade_scheduler_enabled, false)
    stop_if_running()
  end

  @doc "Is the scheduler enabled per current runtime config?"
  def enabled? do
    Application.get_env(:firmware_manager, :upgrade_scheduler_enabled, false)
  end

  @doc "Get the configured interval (ms)."
  def get_interval_ms do
    Application.get_env(:firmware_manager, :upgrade_interval_ms, 300_000)
  end

  @doc "Set the interval (ms). If the scheduler is running, it will be restarted to apply the change."
  def set_interval_ms(ms) when is_integer(ms) and ms > 0 do
    Application.put_env(:firmware_manager, :upgrade_interval_ms, ms)
    # Restart the scheduler to pick up new interval if running
    case Process.whereis(FirmwareManager.UpgradeScheduler) do
      pid when is_pid(pid) ->
        _ = DynamicSupervisor.terminate_child(FirmwareManager.UpgradeSupervisor, pid)
        if enabled?(), do: ensure_started()
        :ok
      _ -> :ok
    end
  end

  defp ensure_started do
    case Process.whereis(FirmwareManager.UpgradeScheduler) do
      nil ->
        spec = %{
          id: FirmwareManager.UpgradeScheduler,
          start: {FirmwareManager.UpgradeScheduler, :start_link, [[interval_ms: get_interval_ms()]]},
          restart: :permanent
        }
        DynamicSupervisor.start_child(FirmwareManager.UpgradeSupervisor, spec)
      _ -> :ok
    end
  end

  defp stop_if_running do
    case Process.whereis(FirmwareManager.UpgradeScheduler) do
      pid when is_pid(pid) -> DynamicSupervisor.terminate_child(FirmwareManager.UpgradeSupervisor, pid)
      _ -> :ok
    end
  end
end

