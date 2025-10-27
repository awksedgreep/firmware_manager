defmodule FirmwareManager.Repo.Migrations.AddSnmpPortAndVirtualToCmts do
  use Ecto.Migration

  def change do
    alter table(:cmts) do
      add :snmp_port, :integer, null: false, default: 161
      add :virtual, :boolean, null: false, default: false
      add :modem_count, :integer, null: false, default: 4
    end
  end
end
