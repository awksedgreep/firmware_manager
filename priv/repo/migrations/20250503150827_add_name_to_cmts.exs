defmodule FirmwareManager.Repo.Migrations.AddNameToCmts do
  use Ecto.Migration

  def change do
    alter table(:cmts) do
      add :name, :string
    end
  end
end
