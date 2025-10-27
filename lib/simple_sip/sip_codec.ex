defmodule SimpleSip.SipCodec do
  @moduledoc false
  @crlf "\r\n"

  def parse_message(binary) when is_binary(binary) do
    with [start_line | rest] <- String.split(binary, @crlf),
         true <- start_line != "",
         {:ok, start} <- parse_start_line(start_line),
         {headers, body} <- split_headers_and_body(rest) do
      {:ok, %{start_line: start, headers: headers, body: body}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp parse_start_line(line) do
    # Request-Line: METHOD SP URI SP SIP/2.0
    case String.split(line, " ", parts: 3) do
      [method, uri, ver] -> {:ok, {method, uri, ver}}
      _ -> {:error, :bad_start}
    end
  end

  defp split_headers_and_body(lines) do
    {header_lines, body_lines} = Enum.split_while(lines, &(&1 != ""))

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

    {headers, body}
  end

  defp split_header(line) do
    case String.split(line, ":", parts: 2) do
      [k, v] -> {String.downcase(String.trim(k)), String.trim(v)}
      _ -> nil
    end
  end

  def header(%{headers: h}, key), do: Map.get(h, String.downcase(key))

  def cseq_method(msg) do
    case header(msg, "cseq") do
      nil -> nil
      v -> v |> String.split(" ") |> List.last()
    end
  end

  def call_id(msg), do: header(msg, "call-id")
  def via(msg), do: header(msg, "via") || header(msg, "v")
  def from(msg), do: header(msg, "from") || header(msg, "f")
  def to(msg), do: header(msg, "to") || header(msg, "t")
  def contact(msg), do: header(msg, "contact")

  def build_response(msg, code, reason, headers, body \\ "") do
    {_m, _uri, ver} = msg.start_line
    start_line = ver <> " " <> Integer.to_string(code) <> " " <> reason

    base = [
      start_line,
      copy_via(msg),
      copy_to_from(msg),
      copy_call_id(msg),
      copy_cseq(msg)
    ]

    extra = Enum.map(headers, fn {k, v} -> k <> ": " <> v end)

    content_headers =
      if body != "" do
        [
          "Content-Type: application/sdp",
          "Content-Length: " <> Integer.to_string(byte_size(body))
        ]
      else
        ["Content-Length: 0"]
      end

    Enum.join(base ++ extra ++ content_headers ++ ["", body], @crlf)
  end

  defp copy_via(msg), do: "Via: " <> (via(msg) || "")

  defp ensure_tag(hdr) do
    if String.contains?(hdr, ";tag=") do
      hdr
    else
      hdr <> ";tag=srvr"
    end
  end

  defp copy_to_from(msg) do
    "To: " <> ensure_tag(to(msg) || "") <> @crlf <> "From: " <> (from(msg) || "")
  end

  defp copy_call_id(msg), do: "Call-ID: " <> (call_id(msg) || "")
  defp copy_cseq(msg), do: "CSeq: " <> (header(msg, "cseq") || "")

  # Common builders
  def build_200(msg),
    do:
      build_response(msg, 200, "OK", [
        {"Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, REGISTER"}
      ])

  def build_options_ok(msg), do: build_200(msg)

  def build_401(msg) do
    realm = SimpleSip.Config.get(:realm, "simple_sip")
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    build_response(msg, 401, "Unauthorized", [
      {"WWW-Authenticate", "Digest realm=\"" <> realm <> "\", nonce=\"" <> nonce <> "\""}
    ])
  end

  def build_501(msg), do: build_response(msg, 501, "Not Implemented", [])

  def build_register_ok(msg) do
    exp = header(msg, "expires") || "300"
    contact = contact(msg) || ""

    build_response(msg, 200, "OK", [
      {"Contact", contact <> ";expires=" <> exp}
    ])
  end

  def build_183_with_sdp(msg, sdp) do
    build_response(msg, 183, "Session Progress", [], sdp)
  end

  def build_bye_ok(msg), do: build_200(msg)

  # SDP helpers
  def sdp_for_rtp({ip1, ip2, ip3, ip4}, rtp_port) do
    ip = Enum.join([ip1, ip2, ip3, ip4], ".")

    [
      "v=0",
      "o=simple_sip 0 0 IN IP4 " <> ip,
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
    # returns {ip, port} or nil
    ip =
      sdp
      |> String.split(@crlf)
      |> Enum.find_value(fn line ->
        case line do
          "c=IN IP4 " <> rest -> rest
          _ -> nil
        end
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
