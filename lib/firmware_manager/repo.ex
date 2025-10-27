defmodule FirmwareManager.Repo do
  use Ecto.Repo,
    otp_app: :firmware_manager,
    adapter: Ecto.Adapters.SQLite3
end
