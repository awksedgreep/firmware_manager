defmodule FirmwareManager.Modem.Cmts do
  @moduledoc "CMTS (Cable Modem Termination System) configuration"

  use Ash.Resource,
    domain: FirmwareManager.Modem,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo FirmwareManager.Repo
    table "cmts"
  end

  actions do
    # No defaults needed as we define all actions explicitly
    
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end

    create :create do
      accept [:name, :ip, :snmp_read, :modem_snmp_read, :modem_snmp_write]
    end

    update :update do
      accept [:name, :ip, :snmp_read, :modem_snmp_read, :modem_snmp_write]
    end
    
    destroy :destroy do
      primary? true
    end
  end

  attributes do
    # Primary key
    uuid_primary_key :id

    # Name of the CMTS
    attribute :name, :string, allow_nil?: true, sortable?: true

    # IP address of the CMTS
    attribute :ip, :string, allow_nil?: false, sortable?: true

    # SNMP read community string for the CMTS
    attribute :snmp_read, :string, allow_nil?: false

    # SNMP read community string for modems
    attribute :modem_snmp_read, :string, allow_nil?: false

    # SNMP write community string for modems
    attribute :modem_snmp_write, :string, allow_nil?: false

    # Timestamps for creation and updates
    timestamps()
  end
end
