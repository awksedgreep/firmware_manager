defmodule SimpleSip.Config do
  @moduledoc false

  def get(key, default \\ nil) do
    opts = Application.get_env(:firmware_manager, :simple_sip, [])
    Keyword.get(opts, key, default)
  end
end
