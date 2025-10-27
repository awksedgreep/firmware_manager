defmodule SimpleSip.MgcpRegistrar do
  use GenServer
  require Logger

  # Tracks MGCP endpoints (AUEP/AUCX) and simulates registration/auth acceptance.
  # State: %{ devices: %{id => %{ip: tuple, port: int, expires_at: int, observed: integer}} }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{devices: %{}}, {:continue, :schedule_purge}}
  end

  @impl true
  def handle_continue(:schedule_purge, state) do
    Process.send_after(self(), :purge, 60_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:purge, state) do
    now = System.system_time(:second)

    devices =
      state.devices
      |> Enum.reject(fn {_id, v} -> v.expires_at && v.expires_at < now end)
      |> Map.new()

    Process.send_after(self(), :purge, 60_000)
    {:noreply, %{state | devices: devices}}
  end

  def upsert_device(id, ip, port, ttl_sec \\ 300) do
    GenServer.cast(__MODULE__, {:upsert, id, ip, port, ttl_sec})
  end

  def get_device(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @impl true
  def handle_cast({:upsert, id, ip, port, ttl_sec}, state) do
    now = System.system_time(:second)
    entry = %{ip: ip, port: port, expires_at: now + ttl_sec, observed: now}
    Logger.info("MGCP registered device id=#{id} peer=#{:inet.ntoa(ip)}:#{port}")
    {:noreply, put_in(state, [:devices, id], entry)}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    {:reply, Map.get(state.devices, id), state}
  end
end
