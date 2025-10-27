defmodule FirmwareManager.LogRetention do
  @moduledoc "Deletes old upgrade logs daily at 3 AM (UTC) to keep the table lean."
  use GenServer
  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_next_run()
    {:ok, state}
  end

  @impl true
  def handle_info(:run, state) do
    cutoff = DateTime.utc_now() |> DateTime.add(-90, :day)
    {deleted, _} = FirmwareManager.Modem.delete_old_upgrade_logs(cutoff)
    Logger.info("LogRetention: deleted #{deleted} upgrade_logs older than #{cutoff}")
    schedule_next_run()
    {:noreply, state}
  end

  defp schedule_next_run do
    now = DateTime.utc_now()
    # Target is 03:00 UTC next occurrence
    target_today = %DateTime{now | hour: 3, minute: 0, second: 0, microsecond: {0, 0}}

    next =
      if DateTime.compare(now, target_today) == :lt do
        target_today
      else
        DateTime.add(target_today, 86_400, :second)
      end

    ms = DateTime.diff(next, now, :millisecond)
    Process.send_after(self(), :run, max(ms, 0))
  end
end
