defmodule SimpleSip.MgcpCodec do
  @moduledoc false
  @crlf "\r\n"

  def parse_message(binary) when is_binary(binary) do
    lines = String.split(binary, @crlf)

    with [first | rest] <- lines,
         {:ok, {verb, txid, endpoint}} <- parse_first_line(first) do
      {header_lines, body_lines} = Enum.split_while(rest, &(&1 != ""))

      headers =
        header_lines
        |> Enum.map(&split_header/1)
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      body =
        case body_lines do
          ["" | tail] -> Enum.join(tail, @crlf)
          _ -> ""
        end

      {:ok, %{verb: verb, txn_id: txid, endpoint: endpoint, headers: headers, body: body}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp parse_first_line(line) do
    # e.g., "CRCX 1234 aaln/1@mg MGCP 1.0" or without trailing version
    parts = String.split(line, " ")

    case parts do
      [verb, txid, endpoint | _rest] -> {:ok, {verb, txid, endpoint}}
      _ -> {:error, :bad_start}
    end
  end

  defp split_header(line) do
    case String.split(line, ":", parts: 2) do
      [k, v] -> {String.downcase(String.trim(k)), String.trim(v)}
      _ -> nil
    end
  end

  def header(%{headers: h}, key), do: Map.get(h, String.downcase(key))

  def build_response(msg, code, reason, headers, body \\ "") do
    start = Integer.to_string(code) <> " " <> (msg.txn_id || "0") <> " " <> reason

    extra = Enum.map(headers, fn {k, v} -> k <> ": " <> v end)

    content_headers =
      if body != "" do
        [
          "Content-Length: " <> Integer.to_string(byte_size(body))
        ]
      else
        ["Content-Length: 0"]
      end

    Enum.join([start] ++ extra ++ content_headers ++ ["", body], @crlf)
  end

  def build_200(msg, headers \\ [], body \\ ""), do: build_response(msg, 200, "OK", headers, body)

  # SDP helpers (reuse SIP style)
  def sdp_for_rtp({ip1, ip2, ip3, ip4}, rtp_port) do
    ip = Enum.join([ip1, ip2, ip3, ip4], ".")

    [
      "v=0",
      "o=mgcp 0 0 IN IP4 " <> ip,
      "s=-",
      "c=IN IP4 " <> ip,
      "t=0 0",
      "m=audio " <> Integer.to_string(rtp_port) <> " RTP/AVP 0",
      "a=rtpmap:0 PCMU/8000",
      "a=ptime:20"
    ]
    |> Enum.join(@crlf)
  end

  def parse_sdp_rtp_target(sdp) do
    ip =
      sdp
      |> String.split(@crlf)
      |> Enum.find_value(fn
        "c=IN IP4 " <> rest -> rest
        _ -> nil
      end)

    port =
      sdp
      |> String.split(@crlf)
      |> Enum.find_value(fn line ->
        case String.split(line, " ") do
          ["m=audio", p | _] -> String.to_integer(p)
          _ -> nil
        end
      end)

    with ip when is_binary(ip) <- ip,
         port when is_integer(port) <- port,
         {:ok, tuple_ip} <- :inet.parse_address(String.to_charlist(ip)) do
      {tuple_ip, port}
    else
      _ -> nil
    end
  end
end
