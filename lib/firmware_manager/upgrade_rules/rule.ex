defmodule FirmwareManager.UpgradeRules.Rule do
  @moduledoc "Persisted upgrade rule (CMTS-agnostic)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "upgrade_rules" do
    field :name, :string
    field :description, :string
    field :mac_rule, :string
    field :sysdescr_glob, :string
    field :firmware_file, :string
    field :tftp_server, :string
    field :enabled, :boolean, default: true
    timestamps()
  end

  def create_changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name, :description, :mac_rule, :sysdescr_glob, :firmware_file, :tftp_server, :enabled])
    |> validate_required([:name, :firmware_file])
  end

  def update_changeset(struct, attrs), do: create_changeset(struct, attrs)
end
