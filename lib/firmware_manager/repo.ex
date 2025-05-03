defmodule FirmwareManager.Repo do
  use AshSqlite.Repo,
    otp_app: :firmware_manager
end
