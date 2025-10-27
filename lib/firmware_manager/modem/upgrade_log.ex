defmodule FirmwareManager.Modem.UpgradeLog do
  @moduledoc "Logs firmware upgrades for modems"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "upgrade_logs" do
    field :mac_address, :string
    field :old_sysdescr, :string
    field :new_sysdescr, :string
    field :new_firmware, :string
    field :rule_id, :binary_id
    field :upgraded_at, :utc_datetime
  end

  def create_changeset(struct, attrs) do
    struct
    |> cast(attrs, [:mac_address, :old_sysdescr, :new_sysdescr, :new_firmware, :upgraded_at, :rule_id])
    |> validate_required([:mac_address, :old_sysdescr, :new_sysdescr, :new_firmware])
    |> put_default_upgraded_at()
  end

  defp put_default_upgraded_at(changeset) do
    case get_field(changeset, :upgraded_at) do
      nil -> put_change(changeset, :upgraded_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end
end
