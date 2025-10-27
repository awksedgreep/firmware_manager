defmodule SimpleSip.RtpPortAllocator do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    start_port = SimpleSip.Config.get(:rtp_port_start, 20000)
    end_port = SimpleSip.Config.get(:rtp_port_end, 20019)
    {:ok, %{range: start_port..end_port, in_use: MapSet.new()}}
  end

  def checkout() do
    GenServer.call(__MODULE__, :checkout)
  end

  def checkin(port) when is_integer(port) do
    GenServer.cast(__MODULE__, {:checkin, port})
  end

  @impl true
  def handle_call(:checkout, _from, %{range: range, in_use: in_use} = state) do
    port = Enum.find(range, fn p -> not MapSet.member?(in_use, p) end)

    if port do
      {:reply, {:ok, port}, %{state | in_use: MapSet.put(in_use, port)}}
    else
      {:reply, {:error, :none_available}, state}
    end
  end

  @impl true
  def handle_cast({:checkin, port}, %{in_use: in_use} = state) do
    {:noreply, %{state | in_use: MapSet.delete(in_use, port)}}
  end
end
