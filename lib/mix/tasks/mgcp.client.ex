defmodule Mix.Tasks.Mgcp.Client do
  use Mix.Task
  require Logger

  @shortdoc "Simple MGCP client to register and request dial-tone (CRCX or off-hook via NTFY)"

  @impl true
  def run(args) do
    # Start only what the client needs; do not start the SimpleSip application
    {:ok, _} = Application.ensure_all_started(:crypto)
    {:ok, _} = Application.ensure_all_started(:logger)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [server: :string, duration: :integer, endpoint: :string, offhook: :boolean]
      )

    server = Keyword.get(opts, :server, "127.0.0.1")
    duration = Keyword.get(opts, :duration, 10)
    endpoint = Keyword.get(opts, :endpoint, "aaln/1@lab")
    offhook? = Keyword.get(opts, :offhook, false)

    {:ok, server_ip} = :inet.parse_address(String.to_charlist(server))

    {:ok, mgcp_sock} = :gen_udp.open(0, [:binary, {:active, true}])
    {:ok, rtp_sock} = :gen_udp.open(0, [:binary, {:active, true}])
    {:ok, {{_a, _b, _c, _d} = local_ip, rtp_port}} = :inet.sockname(rtp_sock)

    # 1) Register device (AUEP)
    txid1 = random_txid()
    auep = ["AUEP ", txid1, " ", endpoint, " MGCP 1.0", "\r\n\r\n"] |> IO.iodata_to_binary()
    send_mgcp(mgcp_sock, server_ip, 2427, auep)
    wait_for_200(txid1)

    # 2) Start tone via CRCX or off-hook (NTFY)
    conn_id =
      if offhook? do
        # Optionally send RQNT (not required by server)
        txid_rqnt = random_txid()

        rqnt =
          ["RQNT ", txid_rqnt, " ", endpoint, " MGCP 1.0", "\r\n\r\n"] |> IO.iodata_to_binary()

        send_mgcp(mgcp_sock, server_ip, 2427, rqnt)
        _ = wait_for_200(txid_rqnt)

        # NTFY with off-hook event and SDP to our RTP port
        txid_ntfy = random_txid()
        sdp = build_sdp_offer(local_ip, rtp_port)

        ntfy =
          [
            "NTFY ",
            txid_ntfy,
            " ",
            endpoint,
            " MGCP 1.0\r\n",
            "O: hd\r\n\r\n",
            sdp
          ]
          |> IO.iodata_to_binary()

        send_mgcp(mgcp_sock, server_ip, 2427, ntfy)
        _ = wait_for_200(txid_ntfy)
        nil
      else
        txid2 = random_txid()
        sdp = build_sdp_offer(local_ip, rtp_port)

        crcx =
          [
            "CRCX ",
            txid2,
            " ",
            endpoint,
            " MGCP 1.0\r\n",
            "C: 1\r\n",
            "M: sendrecv\r\n\r\n",
            sdp
          ]
          |> IO.iodata_to_binary()

        send_mgcp(mgcp_sock, server_ip, 2427, crcx)

        case wait_for_200_and_conn_id(txid2) do
          {:ok, id} -> id
          _ -> nil
        end
      end

    # 3) Count RTP for duration
    rtp_count = listen_rtp(rtp_sock, duration)
    Logger.info("RTP packets received: #{rtp_count}")

    # 4) Cleanup: DLCX if we have conn-id
    if conn_id do
      txid3 = random_txid()

      dlcx =
        [
          "DLCX ",
          txid3,
          " ",
          endpoint,
          " MGCP 1.0\r\n",
          "I: ",
          conn_id,
          "\r\n\r\n"
        ]
        |> IO.iodata_to_binary()

      send_mgcp(mgcp_sock, server_ip, 2427, dlcx)
      _ = wait_for_200(txid3)
    end

    :ok
  end

  defp send_mgcp(sock, ip, port, payload), do: :gen_udp.send(sock, ip, port, payload)

  defp wait_for_200(txid) do
    receive do
      {:udp, _s, _ip, _p, pkt} ->
        case SimpleSip.MgcpCodec.parse_message(pkt) do
          {:ok, %{verb: code, txn_id: ^txid}} when code in ["200", 200] -> :ok
          _ -> wait_for_200(txid)
        end
    after
      2000 -> :timeout
    end
  end

  defp wait_for_200_and_conn_id(txid) do
    receive do
      {:udp, _s, _ip, _p, pkt} ->
        case SimpleSip.MgcpCodec.parse_message(pkt) do
          {:ok, %{verb: code, txn_id: ^txid} = msg} when code in ["200", 200] ->
            {:ok, SimpleSip.MgcpCodec.header(msg, "i")}

          _ ->
            wait_for_200_and_conn_id(txid)
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

  defp build_sdp_offer({a, b, c, d}, rtp_port) do
    ip = Enum.join([a, b, c, d], ".")

    [
      "v=0\r\n",
      "o=client 0 0 IN IP4 ",
      ip,
      "\r\n",
      "s=-\r\n",
      "c=IN IP4 ",
      ip,
      "\r\n",
      "t=0 0\r\n",
      "m=audio ",
      Integer.to_string(rtp_port),
      " RTP/AVP 0\r\n",
      "a=rtpmap:0 PCMU/8000\r\n",
      "a=ptime:20\r\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp random_txid(), do: Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
end
