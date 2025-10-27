defmodule SimpleSip.SipListener do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    ip = SimpleSip.Config.get(:sip_ip, {0, 0, 0, 0})
    port = SimpleSip.Config.get(:sip_port, 5060)

    opts = [
      :binary,
      {:ip, ip},
      {:active, true},
      {:reuseaddr, true}
    ]

    socket =
      case :gen_udp.open(port, opts) do
        {:ok, sock} ->
          sock

        {:error, :eaddrinuse} when port != 0 ->
          Logger.warning("SIP port #{port} in use; falling back to ephemeral port")

          case :gen_udp.open(0, opts) do
            {:ok, sock} -> sock
            other -> raise "Failed to open SIP UDP socket: #{inspect(other)}"
          end

        other ->
          raise "Failed to open SIP UDP socket: #{inspect(other)}"
      end

    {:ok, {_, actual_port}} = :inet.sockname(socket)
    Logger.info("SIP UDP listener started on #{:inet.ntoa(ip)}:#{actual_port}")
    state = %{socket: socket, peers: MapSet.new()}
    {:ok, state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, packet}, %{peers: peers} = state) do
    peer = {ip, port}

    case SimpleSip.SipCodec.parse_message(packet) do
      {:ok, msg} ->
        user = extract_user(msg)
        peer_str = peer_string(ip, port)

        new_peers =
          if MapSet.member?(peers, peer) do
            peers
          else
            Logger.info("New SIP client #{peer_str} user=#{user || "-"}")
            MapSet.put(peers, peer)
          end

        method = elem(msg.start_line, 0)
        call_id = SimpleSip.SipCodec.call_id(msg)

        if SimpleSip.Config.get(:log_verbose, true) do
          Logger.info(
            "SIP #{method} from #{peer_str} user=#{user || "-"} call-id=#{call_id || "-"}"
          )
        end

        handle_message(socket, peer, msg)
        {:noreply, %{state | peers: new_peers}}

      {:error, reason} ->
        Logger.debug("Failed to parse SIP: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_message(socket, peer, %{start_line: {method, _uri, _ver}} = msg) do
    case method do
      "OPTIONS" ->
        reply = SimpleSip.SipCodec.build_options_ok(msg)
        send_packet(socket, peer, reply)

      "REGISTER" ->
        reply = SimpleSip.Registrar.handle_register(msg)
        send_packet(socket, peer, reply)

      "INVITE" ->
        {:ok, reply} = SimpleSip.Session.handle_invite(msg, peer)
        send_packet(socket, peer, reply)

      "BYE" ->
        reply = SimpleSip.Session.handle_bye(msg)
        send_packet(socket, peer, reply)

      "CANCEL" ->
        reply = SimpleSip.SipCodec.build_200(msg)
        send_packet(socket, peer, reply)

      other ->
        Logger.debug("Unhandled method #{other}")
        send_packet(socket, peer, SimpleSip.SipCodec.build_501(msg))
    end
  end

  defp send_packet(socket, {ip, port}, payload) do
    :gen_udp.send(socket, ip, port, payload)
  end

  defp peer_string(ip, port), do: to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port)

  defp extract_user(msg) do
    # Prefer From header, fallback to To
    src = SimpleSip.SipCodec.from(msg) || SimpleSip.SipCodec.to(msg) || ""

    case Regex.run(~r/sip:([^@>;\s]+)/, src) do
      [_, user] -> user
      _ -> nil
    end
  end
end
