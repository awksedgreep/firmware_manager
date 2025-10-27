defmodule SimpleSip.MgcpSession do
  use GenServer
  require Logger

  # One session per Connection-ID

  def start_link(opts) do
    conn_id = Keyword.fetch!(opts, :conn_id)
    GenServer.start_link(__MODULE__, opts, name: via(conn_id))
  end

  defp via(conn_id), do: {:via, Registry, {SimpleSip.MgcpSessionRegistry, conn_id}}

  @impl true
  def init(opts) do
    state = %{
      conn_id: Keyword.fetch!(opts, :conn_id),
      peer: Keyword.get(opts, :peer),
      rtp_port: Keyword.get(opts, :rtp_port),
      local_ip: Keyword.get(opts, :local_ip),
      tone_pid: Keyword.get(opts, :tone_pid)
    }

    {:ok, state}
  end

  def handle_crcx(msg, peer) do
    {:ok, rtp_port} = SimpleSip.RtpPortAllocator.checkout()
    {:ok, local_ip} = local_ip_for_reply()
    sdp = SimpleSip.MgcpCodec.sdp_for_rtp(local_ip, rtp_port)

    target = SimpleSip.MgcpCodec.parse_sdp_rtp_target(msg.body)

    tone_pid =
      case target do
        {ip, port} ->
          {:ok, pid} = SimpleSip.RtpTone.start_link(dest_ip: ip, dest_port: port)
          pid

        _ ->
          nil
      end

    conn_id = random_hex(8)

    case DynamicSupervisor.start_child(SimpleSip.MgcpSessionSupervisor, {
           __MODULE__,
           conn_id: conn_id,
           peer: peer,
           rtp_port: rtp_port,
           local_ip: local_ip,
           tone_pid: tone_pid
         }) do
      {:ok, _pid} ->
        {peer_ip, peer_port} = peer

        Logger.info(
          "MGCP session started conn-id=#{conn_id} peer=#{:inet.ntoa(peer_ip)}:#{peer_port}"
        )

        {:ok, SimpleSip.MgcpCodec.build_200(msg, [{"I", conn_id}], sdp)}

      {:error, {:already_started, _pid}} ->
        {:ok, SimpleSip.MgcpCodec.build_200(msg)}

      other ->
        other
    end
  end

  def handle_dlcx(msg) do
    conn_id = SimpleSip.MgcpCodec.header(msg, "i")

    if conn_id do
      case Registry.lookup(SimpleSip.MgcpSessionRegistry, conn_id) do
        [{pid, _}] -> GenServer.cast(pid, :bye)
        _ -> :ok
      end
    end

    SimpleSip.MgcpCodec.build_200(msg)
  end

  def handle_mdcx(msg) do
    conn_id = SimpleSip.MgcpCodec.header(msg, "i")
    sdp_target = SimpleSip.MgcpCodec.parse_sdp_rtp_target(msg.body)

    case Registry.lookup(SimpleSip.MgcpSessionRegistry, conn_id) do
      [{pid, _}] -> GenServer.cast(pid, {:mdcx, sdp_target})
      _ -> :ok
    end

    SimpleSip.MgcpCodec.build_200(msg)
  end

  def handle_ntfy(msg, peer) do
    # If NTFY indicates off-hook (hd), start dial tone by ensuring a session exists.
    events = SimpleSip.MgcpCodec.header(msg, "o") || SimpleSip.MgcpCodec.header(msg, "ob") || ""
    has_offhook = String.contains?(events, "hd")

    if has_offhook do
      # Create a temporary session using endpoint as ID if none exists; send 200 OK
      {:ok, rtp_port} = SimpleSip.RtpPortAllocator.checkout()
      {:ok, local_ip} = local_ip_for_reply()

      target = SimpleSip.MgcpCodec.parse_sdp_rtp_target(msg.body)

      tone_pid =
        case target do
          {ip, port} ->
            {:ok, pid} = SimpleSip.RtpTone.start_link(dest_ip: ip, dest_port: port)
            pid

          _ ->
            nil
        end

      conn_id = SimpleSip.MgcpCodec.header(msg, "i") || random_hex(8)

      case Registry.lookup(SimpleSip.MgcpSessionRegistry, conn_id) do
        [] ->
          _ =
            DynamicSupervisor.start_child(SimpleSip.MgcpSessionSupervisor, {
              __MODULE__,
              conn_id: conn_id,
              peer: peer,
              rtp_port: rtp_port,
              local_ip: local_ip,
              tone_pid: tone_pid
            })

        _ ->
          :ok
      end

      SimpleSip.MgcpCodec.build_200(msg)
    else
      SimpleSip.MgcpCodec.build_200(msg)
    end
  end

  @impl true
  def handle_cast(:bye, state) do
    if state.tone_pid, do: Process.exit(state.tone_pid, :normal)
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:mdcx, target}, state) do
    if state.tone_pid, do: Process.exit(state.tone_pid, :normal)

    tone_pid =
      case target do
        {ip, port} ->
          {:ok, pid} = SimpleSip.RtpTone.start_link(dest_ip: ip, dest_port: port)
          pid

        _ ->
          nil
      end

    {:noreply, %{state | tone_pid: tone_pid}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.tone_pid, do: Process.exit(state.tone_pid, :normal)
    if state.rtp_port, do: SimpleSip.RtpPortAllocator.checkin(state.rtp_port)
    :ok
  end

  defp local_ip_for_reply() do
    ip = SimpleSip.Config.get(:sip_ip, {0, 0, 0, 0})

    case ip do
      {0, 0, 0, 0} -> {:ok, {127, 0, 0, 1}}
      _ -> {:ok, ip}
    end
  end

  defp random_hex(nbytes), do: Base.encode16(:crypto.strong_rand_bytes(nbytes), case: :lower)
end
