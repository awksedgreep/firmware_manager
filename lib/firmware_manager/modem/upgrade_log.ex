defmodule FirmwareManager.Modem.UpgradeLog do
  @moduledoc "Logs firmware upgrades for modems"

  use Ash.Resource,
    domain: FirmwareManager.Modem,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo FirmwareManager.Repo
    table "upgrade_logs"
  end

  actions do
    defaults [:create]
    
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end
  end

  identities do
    identity :by_mac_address, [:mac_address]
  end

  calculations do
    calculate :formatted_date, :string, expr(fragment("strftime('%Y-%m-%d %H:%M:%S', ?) as formatted_date", upgraded_at))
  end

  attributes do
    # Primary key
    uuid_primary_key :id

    # MAC address of the modem
    attribute :mac_address, :string, allow_nil?: false, sortable?: true

    # Previous system description
    attribute :old_sysdescr, :string, allow_nil?: false

    # New system description
    attribute :new_sysdescr, :string, allow_nil?: false

    # New firmware version
    attribute :new_firmware, :string, allow_nil?: false

    # Timestamp of the upgrade
    attribute :upgraded_at, :utc_datetime, default: &DateTime.utc_now/0, allow_nil?: false, sortable?: true
  end
end
