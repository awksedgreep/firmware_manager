defmodule FirmwareManager.UpgradeRules do
  @moduledoc "Ash domain for upgrade rules."
  use Ash.Domain, otp_app: :firmware_manager

  resources do
    resource FirmwareManager.UpgradeRules.Rule
  end
end

