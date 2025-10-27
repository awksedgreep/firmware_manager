defmodule SimpleSip.RtpTone do
  use GenServer
  require Logger
  import Bitwise

  @packet_interval_ms 20
  # 20ms at 8kHz
  @ptime_samples 160
  @pt_pcmu 0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    dest_ip = Keyword.fetch!(opts, :dest_ip)
    dest_port = Keyword.fetch!(opts, :dest_port)

    {:ok, sock} = :gen_udp.open(0, [:binary, {:active, false}])

    state = %{
      sock: sock,
      dest_ip: dest_ip,
      dest_port: dest_port,
      seq: :rand.uniform(65535) - 1,
      ts: :rand.uniform(1_000_000),
      ssrc: :rand.uniform(4_294_967_295),
      frame: precompute_pcmu_frame()
    }

    Process.send_after(self(), :tick, @packet_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    packet = build_rtp(state)
    :ok = :gen_udp.send(state.sock, state.dest_ip, state.dest_port, packet)

    next = %{state | seq: state.seq + 1 &&& 0xFFFF, ts: state.ts + @ptime_samples &&& 0xFFFFFFFF}

    Process.send_after(self(), :tick, @packet_interval_ms)
    {:noreply, next}
  end

  @impl true
  def terminate(_reason, state) do
    :gen_udp.close(state.sock)
    :ok
  end

  defp build_rtp(state) do
    # RTP header: V=2,P=0,X=0,CC=0,M=0,PT=0
    <<2::2, 0::1, 0::1, 0::4, 0::1, @pt_pcmu::7, state.seq::16, state.ts::32, state.ssrc::32,
      state.frame::binary>>
  end

  defp precompute_pcmu_frame() do
    # Generate 20ms of dual-tone (350Hz + 440Hz) at 8kHz and μ-law encode
    tone =
      for n <- 0..(@ptime_samples - 1), into: <<>> do
        t = n / 8000.0
        # amplitude keep small to avoid clipping before μ-law
        sample =
          :math.sin(2 * :math.pi() * 350 * t) * 0.3 + :math.sin(2 * :math.pi() * 440 * t) * 0.3

        pcm16 = trunc(sample * 32767)
        <<linear2ulaw(pcm16)>>
      end

    tone
  end

  # μ-law encoder (G.711) for 16-bit PCM to 8-bit μ-law
  defp linear2ulaw(sample) when is_integer(sample) do
    sample =
      cond do
        sample > 32767 -> 32767
        sample < -32768 -> -32768
        true -> sample
      end

    sign = if sample < 0, do: 0x00, else: 0x80
    # bias
    sample = abs(sample) + 132
    sample = if sample > 0x1FFF, do: 0x1FFF, else: sample

    segment = segment(sample)

    mantissa =
      if segment >= 2 do
        sample >>> (segment + 3) &&& 0x0F
      else
        sample >>> 4 &&& 0x0F
      end

    ulaw = bnot(sign ||| segment <<< 4 ||| mantissa) &&& 0xFF
    ulaw
  end

  defp segment(sample) do
    cond do
      sample >= 0x1000 -> 7
      sample >= 0x0800 -> 6
      sample >= 0x0400 -> 5
      sample >= 0x0200 -> 4
      sample >= 0x0100 -> 3
      sample >= 0x0080 -> 2
      sample >= 0x0040 -> 1
      true -> 0
    end
  end
end
