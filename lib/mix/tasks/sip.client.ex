defmodule Mix.Tasks.Sip.Client do
  use Mix.Task
  require Logger

  @shortdoc "Simple SIP client to register and request dial-tone"

  @impl true
  def run(args) do
    # Start only what the client needs; do not start the SimpleSip application
    {:ok, _} = Application.ensure_all_started(:crypto)
    {:ok, _} = Application.ensure_all_started(:logger)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          server: :string,
          port: :integer,
          duration: :integer,
          user: :string,
          offhook: :boolean
        ]
      )

    server = Keyword.get(opts, :server, "127.0.0.1")
    port = Keyword.get(opts, :port, SimpleSip.Config.get(:sip_port, 5060))
    duration = Keyword.get(opts, :duration, 10)
    user = Keyword.get(opts, :user, "lab")
    _offhook? = Keyword.get(opts, :offhook, false)

    {:ok, server_ip} = :inet.parse_address(String.to_charlist(server))

    {:ok, sip_sock} = :gen_udp.open(0, [:binary, {:active, true}])

    # Offer a local RTP port to receive tone
    {:ok, rtp_sock} = :gen_udp.open(0, [:binary, {:active, true}])
    {:ok, {{_a, _b, _c, _d} = local_ip, rtp_port}} = :inet.sockname(rtp_sock)

    call_id = random_hex(12)

    # REGISTER without auth, expect 401, then REGISTER with auth
    reg1 = build_register(user, server_ip, call_id)
    send_sip(sip_sock, server_ip, port, reg1)

    auth = wait_for_401()

    reg2 = build_register(user, server_ip, call_id, auth)
    send_sip(sip_sock, server_ip, port, reg2)
    _ = wait_for_200()

    # INVITE with SDP (off-hook)
    sdp = build_sdp_offer(local_ip, rtp_port)
    invite = build_invite(user, server_ip, call_id, sdp)
    send_sip(sip_sock, server_ip, port, invite)

    rtp_count = listen_rtp(rtp_sock, duration)
    Logger.info("RTP packets received: #{rtp_count}")

    # BYE
    bye = build_bye(user, server_ip, call_id)
    send_sip(sip_sock, server_ip, port, bye)

    :ok
  end

  defp send_sip(sock, ip, port, payload) do
    :gen_udp.send(sock, ip, port, payload)
  end

  defp wait_for_401() do
    receive do
      {:udp, _s, _ip, _p, pkt} ->
        case SimpleSip.SipCodec.parse_message(pkt) do
          {:ok, %{start_line: {"SIP/2.0", "401", _}, headers: h}} ->
            Map.get(h, "www-authenticate")

          {:ok, %{start_line: {_, _, _}}} ->
            wait_for_401()

          _ ->
            wait_for_401()
        end
    after
      2000 -> nil
    end
  end

  defp wait_for_200() do
    receive do
      {:udp, _s, _ip, _p, pkt} ->
        case SimpleSip.SipCodec.parse_message(pkt) do
          {:ok, %{start_line: {"SIP/2.0", "200", _}}} -> :ok
          _ -> wait_for_200()
        end
    after
      2000 -> :timeout
    end
  end

  defp listen_rtp(rtp_sock, seconds) do
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    loop_rtp(rtp_sock, 0, deadline)
  end

  defp loop_rtp(rtp_sock, count, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      count
    else
      receive do
        {:udp, ^rtp_sock, _ip, _port, _pkt} -> loop_rtp(rtp_sock, count + 1, deadline)
      after
        200 -> loop_rtp(rtp_sock, count, deadline)
      end
    end
  end

  defp build_register(user, ip, call_id, auth_hdr \\ nil) do
    ipstr = ip |> :inet.ntoa() |> to_string()
    contact = "<sip:" <> user <> ":5060@" <> ipstr <> ">"
    via = "SIP/2.0/UDP " <> ipstr <> ";branch=z9hG4bK" <> random_hex(8)

    lines =
      [
        "REGISTER sip:" <> ipstr <> " SIP/2.0",
        "Via: " <> via,
        "From: \"lab\" <sip:" <> user <> "@lab>",
        "To: <sip:" <> user <> "@lab>",
        "Call-ID: " <> call_id,
        "CSeq: 1 REGISTER",
        "Contact: " <> contact,
        "Expires: 300"
      ] ++
        if(auth_hdr, do: ["Authorization: " <> auth_hdr], else: []) ++ ["Content-Length: 0", ""]

    Enum.join(lines, "\r\n")
  end

  defp build_invite(user, ip, call_id, sdp) do
    ipstr = ip |> :inet.ntoa() |> to_string()
    via = "SIP/2.0/UDP " <> ipstr <> ";branch=z9hG4bK" <> random_hex(8)
    sdp_len = byte_size(sdp)

    [
      "INVITE sip:" <> ipstr <> " SIP/2.0",
      "Via: " <> via,
      "From: \"lab\" <sip:" <> user <> "@lab>",
      "To: <sip:" <> user <> "@lab>",
      "Call-ID: " <> call_id,
      "CSeq: 2 INVITE",
      "Contact: <sip:" <> user <> "@lab>",
      "Content-Type: application/sdp",
      "Content-Length: " <> Integer.to_string(sdp_len),
      "",
      sdp
    ]
    |> Enum.join("\r\n")
  end

  defp build_bye(user, ip, call_id) do
    ipstr = ip |> :inet.ntoa() |> to_string()
    via = "SIP/2.0/UDP " <> ipstr <> ";branch=z9hG4bK" <> random_hex(8)

    [
      "BYE sip:" <> ipstr <> " SIP/2.0",
      "Via: " <> via,
      "From: \"lab\" <sip:" <> user <> "@lab>",
      "To: <sip:" <> user <> "@lab>;tag=srvr",
      "Call-ID: " <> call_id,
      "CSeq: 3 BYE",
      "Content-Length: 0",
      ""
    ]
    |> Enum.join("\r\n")
  end

  defp build_sdp_offer({a, b, c, d}, rtp_port) do
    ip = Enum.join([a, b, c, d], ".")

    [
      "v=0",
      "o=client 0 0 IN IP4 " <> ip,
      "s=-",
      "c=IN IP4 " <> ip,
      "t=0 0",
      "m=audio " <> Integer.to_string(rtp_port) <> " RTP/AVP 0",
      "a=rtpmap:0 PCMU/8000",
      "a=ptime:20"
    ]
    |> Enum.join("\r\n")
  end

  defp random_hex(nbytes), do: Base.encode16(:crypto.strong_rand_bytes(nbytes), case: :lower)
end
