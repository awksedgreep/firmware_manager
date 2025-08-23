defmodule FirmwareManager.SNMP.SimBoot do
  @moduledoc """
  On application boot, ensure any CMTS records marked as virtual have a running
  snmpkit simulator on their configured snmp_port.
  """
  use GenServer
  require Logger
  alias FirmwareManager.Modem
  alias FirmwareManager.SNMP.Simulator

  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    # Delay a bit to let Repo and migrations complete
    Process.send_after(self(), :boot, 200)
    {:ok, %{started: 0}}
  end

  @impl true
  def handle_info(:boot, state) do
    virtual_cmts = Modem.list_cmts(filter: [virtual: true])

    count =
      virtual_cmts
      |> Enum.reduce(0, fn cmts, acc ->
        case Simulator.ensure_cmts_sim(cmts) do
          {:ok, port} ->
            Logger.info("Virtual CMTS #{cmts.id} simulator ensured on port #{port}")
            acc + 1

          :noop -> acc
          {:error, reason} ->
            Logger.warning("Failed to start simulator for #{cmts.id}: #{inspect(reason)}")
            acc
        end
      end)

    {:noreply, %{state | started: count}}
  end
end
