defmodule FirmwareManager.Repo.Migrations.CreateUpgradeRules do
  use Ecto.Migration

  def change do
    create table(:upgrade_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :mac_rule, :text, null: false
      add :sysdescr_glob, :text
      add :firmware_file, :text, null: false
      add :tftp_server, :text
      add :enabled, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:upgrade_rules, [:name])
  end
end

