defmodule FirmwareManager.MacCIDR do
  import Bitwise

  @moduledoc """
  MAC address CIDR/mask matching utilities.

  Supports:
  - CIDR-style: "aa:bb:cc:dd:ee:ff/NN" with 0 <= NN <= 48
  - Explicit mask: "aa:bb:cc:dd:ee:ff/ff:ff:f0:00:00:00"

  Provides helpers to parse rules, test matches, and filter modem lists.
  """

  @type mac_int :: non_neg_integer()
  @type rule :: %{network: mac_int(), mask: mac_int()}

  @mac_bits 48
  @mac_max 0xFFFFFFFFFFFF

  @doc """
  Parse a rule string into %{network, mask}.

  Examples:
    parse("aa:bb:cc:00:00:00/24")
    parse("AA-BB-CC-00-00-00/ff:ff:ff:00:00:00")
  """
  @spec parse(String.t()) :: {:ok, rule()} | {:error, term()}
  def parse(rule) when is_binary(rule) do
    case String.split(rule, "/", parts: 2) do
      [base, len_str] when is_binary(len_str) and len_str != "" ->
        with {:ok, base_int} <- mac_to_int(base),
             {:ok, mask} <- parse_mask(len_str) do
          {:ok, %{network: base_int &&& mask, mask: mask}}
        else
          {:error, _} = err -> err
          _ -> {:error, :invalid_rule}
        end

      _ ->
        {:error, :invalid_rule}
    end
  end

  @doc """
  Returns true if the given MAC (string or 6-byte binary) matches the parsed rule.
  """
  @spec mac_match?(String.t() | binary(), rule() | String.t()) :: boolean()
  def mac_match?(mac, %{network: net, mask: mask}) do
    case mac_to_int(mac) do
      {:ok, mac_int} -> (mac_int &&& mask) == net
      _ -> false
    end
  end

  def mac_match?(mac, rule_str) when is_binary(rule_str) do
    case parse(rule_str) do
      {:ok, rule} -> mac_match?(mac, rule)
      _ -> false
    end
  end

  @doc """
  Public API expected by tests: alias of mac_match?/2
  """
  @spec match?(String.t() | binary(), rule() | String.t()) :: boolean()
  def match?(mac, rule), do: mac_match?(mac, rule)

  @doc """
  Filter a list of modem maps like [%{mac: "xx:.."}] by rule.
  """
  @spec filter_modems([map()], rule() | String.t()) :: [map()]
  def filter_modems(modems, rule) when is_list(modems) do
    Enum.filter(modems, fn m ->
      mac = Map.get(m, :mac) || Map.get(m, "mac")
      mac_match?(mac, rule)
    end)
  end

  @doc """
  Convert a MAC string ("aa:bb:..." or "aa-bb-...") or 6-byte binary to 48-bit integer.
  """
  @spec mac_to_int(String.t() | binary()) :: {:ok, mac_int()} | {:error, term()}
  def mac_to_int(<<a, b, c, d, e, f>>) do
    {:ok, a <<< 40 ||| b <<< 32 ||| c <<< 24 ||| d <<< 16 ||| e <<< 8 ||| f}
  end

  def mac_to_int(mac) when is_binary(mac) do
    mac
    |> String.replace("-", ":")
    |> String.downcase()
    |> String.split(":")
    |> case do
      parts when length(parts) == 6 ->
        with {:ok, bytes} <- parse_hex_bytes(parts),
             <<a, b, c, d, e, f>> <- :erlang.list_to_binary(bytes) do
          mac_to_int(<<a, b, c, d, e, f>>)
        else
          _ -> {:error, :invalid_mac}
        end

      _ ->
        {:error, :invalid_mac}
    end
  end

  def mac_to_int(_), do: {:error, :invalid_mac}

  @doc """
  Pretty format a 48-bit integer MAC as aa:bb:cc:dd:ee:ff.
  """
  @spec int_to_mac(mac_int()) :: String.t()
  def int_to_mac(int) when is_integer(int) and int >= 0 and int <= @mac_max do
    <<a::8, b::8, c::8, d::8, e::8, f::8>> = <<int::48>>

    [a, b, c, d, e, f]
    |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
    |> Enum.join(":")
    |> String.downcase()
  end

  # mask can be prefix length (e.g. "24") or explicit hex mask (e.g. "ff:ff:f0:00:00:00")
  defp parse_mask(len) when is_binary(len) do
    cond do
      String.contains?(len, ":") or String.contains?(len, "-") ->
        with {:ok, int} <- mac_to_int(len) do
          {:ok, int &&& @mac_max}
        else
          _ -> {:error, :invalid_mask}
        end

      true ->
        case Integer.parse(len) do
          {n, _} when n >= 0 and n <= @mac_bits ->
            {:ok, prefix_mask(n)}

          _ ->
            {:error, :invalid_mask}
        end
    end
  end

  defp prefix_mask(n) when is_integer(n) and n >= 0 and n <= @mac_bits do
    # n leading 1s in 48-bit space
    if n == 0 do
      0
    else
      ((1 <<< n) - 1) <<< (@mac_bits - n)
    end
  end

  defp parse_hex_bytes(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case Integer.parse(part, 16) do
        {v, ""} when v >= 0 and v <= 255 -> {:cont, {:ok, [v | acc]}}
        _ -> {:halt, {:error, :invalid_mac}}
      end
    end)
    |> case do
      {:ok, bytes} when length(bytes) == 6 -> {:ok, Enum.reverse(bytes)}
      other -> other
    end
  end
end
