defmodule SimpleSip.MgcpListener do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    ip = SimpleSip.Config.get(:sip_ip, {0, 0, 0, 0})
    port = SimpleSip.Config.get(:mgcp_port, 2427)

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
          Logger.warning("MGCP port #{port} in use; falling back to ephemeral port")

          case :gen_udp.open(0, opts) do
            {:ok, sock} -> sock
            other -> raise "Failed to open MGCP UDP socket: #{inspect(other)}"
          end

        other ->
          raise "Failed to open MGCP UDP socket: #{inspect(other)}"
      end

    {:ok, {_, actual_port}} = :inet.sockname(socket)
    Logger.info("MGCP UDP listener started on #{:inet.ntoa(ip)}:#{actual_port}")
    state = %{socket: socket, peers: MapSet.new()}
    {:ok, state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, packet}, %{peers: peers} = state) do
    peer = {ip, port}

    case SimpleSip.MgcpCodec.parse_message(packet) do
      {:ok, msg} ->
        peer_str = peer_string(ip, port)

        new_peers =
          if MapSet.member?(peers, peer) do
            peers
          else
            Logger.info("New MGCP client #{peer_str}")
            MapSet.put(peers, peer)
          end

        if SimpleSip.Config.get(:log_verbose, true) do
          Logger.info("MGCP #{msg.verb} from #{peer_str} txid=#{msg.txn_id}")
        end

        handle_message(socket, peer, msg)
        {:noreply, %{state | peers: new_peers}}

      {:error, reason} ->
        Logger.debug("Failed to parse MGCP: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_message(socket, peer, %{verb: verb} = msg) do
    case verb do
      "AUEP" ->
        # Audit Endpoint used here to "register" device; accept and store
        id = msg.endpoint || peer_to_id(peer)
        SimpleSip.MgcpRegistrar.upsert_device(id, elem(peer, 0), elem(peer, 1))
        send_packet(socket, peer, SimpleSip.MgcpCodec.build_200(msg))

      "AUCX" ->
        id = msg.endpoint || peer_to_id(peer)
        SimpleSip.MgcpRegistrar.upsert_device(id, elem(peer, 0), elem(peer, 1))
        send_packet(socket, peer, SimpleSip.MgcpCodec.build_200(msg))

      "RQNT" ->
        # Request Notification: we "arm" off-hook (hd) and will respond to NTFY
        send_packet(socket, peer, SimpleSip.MgcpCodec.build_200(msg))

      "NTFY" ->
        # Off-hook detection: start dial tone by creating/refreshing a session if SDP present
        reply = SimpleSip.MgcpSession.handle_ntfy(msg, peer)
        send_packet(socket, peer, reply)

      "CRCX" ->
        {:ok, reply} = SimpleSip.MgcpSession.handle_crcx(msg, peer)
        send_packet(socket, peer, reply)

      "MDCX" ->
        reply = SimpleSip.MgcpSession.handle_mdcx(msg)
        send_packet(socket, peer, reply)

      "DLCX" ->
        reply = SimpleSip.MgcpSession.handle_dlcx(msg)
        send_packet(socket, peer, reply)

      _other ->
        # For lab purposes, accept everything
        send_packet(socket, peer, SimpleSip.MgcpCodec.build_200(msg))
    end
  end

  defp peer_to_id({ip, port}), do: to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port)

  defp send_packet(socket, {ip, port}, payload) do
    :gen_udp.send(socket, ip, port, payload)
  end

  defp peer_string(ip, port), do: to_string(:inet.ntoa(ip)) <> ":" <> Integer.to_string(port)
end
