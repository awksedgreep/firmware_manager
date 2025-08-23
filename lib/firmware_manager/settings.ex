defmodule FirmwareManager.Settings do
  @moduledoc """
  Centralized settings accessor. Values can be wired to a future config UI.

  For now, reads from application env:
    config :firmware_manager, tftp_server: "10.0.0.5"
  """

  @app :firmware_manager

  @doc "Return default TFTP server or nil if unset"
  def tftp_server do
    Application.get_env(@app, :tftp_server, nil)
  end
end
