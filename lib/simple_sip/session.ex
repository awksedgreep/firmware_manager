defmodule SimpleSip.Session do
  use GenServer
  require Logger

  # Session per Call-ID; sends 183 with SDP and starts RTP tone

  def start_link(opts) do
    call_id = Keyword.fetch!(opts, :call_id)
    GenServer.start_link(__MODULE__, opts, name: via(call_id))
  end

  defp via(call_id), do: {:via, Registry, {SimpleSip.SessionRegistry, call_id}}

  @impl true
  def init(opts) do
    state = %{
      call_id: Keyword.fetch!(opts, :call_id),
      peer: Keyword.get(opts, :peer),
      invite_msg: Keyword.get(opts, :invite_msg),
      rtp_port: Keyword.get(opts, :rtp_port),
      local_ip: Keyword.get(opts, :local_ip),
      tone_pid: Keyword.get(opts, :tone_pid)
    }

    {:ok, state}
  end

  def handle_invite(msg, peer) do
    call_id = SimpleSip.SipCodec.call_id(msg)

    # Allocate resources and compute reply
    {:ok, rtp_port} = SimpleSip.RtpPortAllocator.checkout()
    {:ok, local_ip} = local_ip_for_reply()
    sdp = SimpleSip.SipCodec.sdp_for_rtp(local_ip, rtp_port)

    target = SimpleSip.SipCodec.parse_sdp_rtp_target(msg.body)

    tone_pid =
      case target do
        {ip, port} ->
          {:ok, pid} = SimpleSip.RtpTone.start_link(dest_ip: ip, dest_port: port)
          pid

        _ ->
          nil
      end

    # Start session process to own these resources
    case DynamicSupervisor.start_child(SimpleSip.SessionSupervisor, {
           __MODULE__,
           call_id: call_id,
           invite_msg: msg,
           peer: peer,
           rtp_port: rtp_port,
           local_ip: local_ip,
           tone_pid: tone_pid
         }) do
      {:ok, _pid} ->
        user = extract_user(msg)
        {peer_ip, peer_port} = peer

        Logger.info(
          "SIP session started user=#{user || "-"} call-id=#{call_id || "-"} peer=#{:inet.ntoa(peer_ip)}:#{peer_port}"
        )

        {:ok, SimpleSip.SipCodec.build_183_with_sdp(msg, sdp)}

      {:error, {:already_started, _pid}} ->
        {:ok, SimpleSip.SipCodec.build_200(msg)}

      other ->
        other
    end
  end

  def handle_bye(msg) do
    call_id = SimpleSip.SipCodec.call_id(msg)
    user = extract_user(msg)
    Logger.info("SIP session ended user=#{user || "-"} call-id=#{call_id || "-"}")

    case Registry.lookup(SimpleSip.SessionRegistry, call_id) do
      [{pid, _}] -> GenServer.cast(pid, :bye)
      _ -> :ok
    end

    SimpleSip.SipCodec.build_bye_ok(msg)
  end

  @impl true
  def handle_cast(:bye, state) do
    if state.tone_pid, do: Process.exit(state.tone_pid, :normal)
    {:stop, :normal, state}
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

  defp extract_user(msg) do
    src = SimpleSip.SipCodec.from(msg) || SimpleSip.SipCodec.to(msg) || ""

    case Regex.run(~r/sip:([^@>;\s]+)/, src) do
      [_, user] -> user
      _ -> nil
    end
  end
end
