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
      accept [:name, :ip, :snmp_read, :snmp_port, :modem_snmp_read, :modem_snmp_write, :virtual, :modem_count]
    end

    update :update do
      accept [:name, :ip, :snmp_read, :snmp_port, :modem_snmp_read, :modem_snmp_write, :virtual, :modem_count]
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

    # SNMP port for CMTS SNMP operations (defaults to 161 for real CMTS; non-standard when virtual)
    attribute :snmp_port, :integer, allow_nil?: false, default: 161

    # SNMP read community string for modems
    attribute :modem_snmp_read, :string, allow_nil?: false

    # SNMP write community string for modems
    attribute :modem_snmp_write, :string, allow_nil?: false

    # Whether this CMTS is simulated via snmpkit
    attribute :virtual, :boolean, allow_nil?: false, default: false

    # Number of simulated modems to populate in virtual mode
    attribute :modem_count, :integer, allow_nil?: false, default: 4

    # Timestamps for creation and updates
    timestamps()
  end
end
