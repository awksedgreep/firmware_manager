defmodule FirmwareManager.Repo.Migrations.AddRuleIdToUpgradeLogs do
  use Ecto.Migration

  def change do
    alter table(:upgrade_logs) do
      add :rule_id, :binary_id
    end

    create index(:upgrade_logs, [:mac_address, :new_firmware])
    create index(:upgrade_logs, [:rule_id])
  end
end

