defmodule SimpleSip.Registrar do
  use GenServer
  require Logger

  # In-memory registrar that accepts any Authorization on second REGISTER
  # State: %{ bindings: %{aor => %{contact: binary, expires_at: integer}} }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{bindings: %{}}, {:continue, :schedule_purge}}
  end

  @impl true
  def handle_continue(:schedule_purge, state) do
    Process.send_after(self(), :purge, 60_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:purge, state) do
    now = System.system_time(:second)

    bindings =
      state.bindings
      |> Enum.reject(fn {_aor, v} -> v.expires_at && v.expires_at < now end)
      |> Map.new()

    Process.send_after(self(), :purge, 60_000)
    {:noreply, %{state | bindings: bindings}}
  end

  def handle_register(msg) do
    has_auth = SimpleSip.SipCodec.header(msg, "authorization")

    if has_auth do
      # accept and store binding
      aor =
        extract_aor(SimpleSip.SipCodec.to(msg)) || extract_aor(SimpleSip.SipCodec.from(msg)) ||
          "sip:any@any"

      contact = SimpleSip.SipCodec.contact(msg) || ""
      exp = (SimpleSip.SipCodec.header(msg, "expires") || "300") |> String.to_integer()
      GenServer.cast(__MODULE__, {:store, aor, contact, exp})

      user = aor_to_user(aor)
      Logger.info("SIP registered user=#{user || "-"} contact=#{contact}")

      SimpleSip.SipCodec.build_register_ok(msg)
    else
      SimpleSip.SipCodec.build_401(msg)
    end
  end

  @impl true
  def handle_cast({:store, aor, contact, exp}, state) do
    now = System.system_time(:second)
    entry = %{contact: contact, expires_at: now + exp}
    {:noreply, put_in(state, [:bindings, aor], entry)}
  end

  defp extract_aor(nil), do: nil

  defp extract_aor(h) do
    case Regex.run(~r/<(sip:[^>]+)>/, h) do
      [_, aor] ->
        aor

      _ ->
        case Regex.run(~r/(sip:[^;>\s]+)/, h) do
          [_, aor] -> aor
          _ -> nil
        end
    end
  end

  defp aor_to_user("sip:" <> rest) do
    case String.split(rest, "@", parts: 2) do
      [user | _] -> user
      _ -> nil
    end
  end

  defp aor_to_user(_), do: nil
end
