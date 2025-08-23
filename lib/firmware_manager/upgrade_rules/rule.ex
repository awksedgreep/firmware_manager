defmodule FirmwareManager.UpgradeRules.Rule do
  @moduledoc "Persisted upgrade rule (CMTS-agnostic)."

  use Ash.Resource,
    domain: FirmwareManager.UpgradeRules,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo FirmwareManager.Repo
    table "upgrade_rules"
  end

  actions do
    defaults []

    read :read do
      primary? true
    end

    create :create do
      accept [:name, :description, :mac_rule, :sysdescr_glob, :firmware_file, :tftp_server, :enabled]
      primary? true
    end

    update :update do
      accept [:name, :description, :mac_rule, :sysdescr_glob, :firmware_file, :tftp_server, :enabled]
    end

    destroy :destroy do
      primary? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: true
    attribute :mac_rule, :string, allow_nil?: true
    attribute :sysdescr_glob, :string, allow_nil?: true
    attribute :firmware_file, :string, allow_nil?: false
    attribute :tftp_server, :string, allow_nil?: true
    attribute :enabled, :boolean, allow_nil?: false, default: true

    timestamps()
  end

  validations do
    validate present([:name, :firmware_file])
  end
end

