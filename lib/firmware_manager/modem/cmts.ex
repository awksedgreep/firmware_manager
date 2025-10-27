defmodule FirmwareManager.Modem.Cmts do
  @moduledoc "CMTS (Cable Modem Termination System) configuration"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cmts" do
    field :name, :string
    field :ip, :string
    field :snmp_read, :string
    field :snmp_port, :integer, default: 161
    field :modem_snmp_read, :string
    field :modem_snmp_write, :string
    field :virtual, :boolean, default: false
    field :modem_count, :integer, default: 4
    timestamps()
  end

  def create_changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name, :ip, :snmp_read, :snmp_port, :modem_snmp_read, :modem_snmp_write, :virtual, :modem_count])
    |> validate_required([:ip, :snmp_read, :modem_snmp_read, :modem_snmp_write])
    |> validate_number(:snmp_port, greater_than: 0)
    |> validate_number(:modem_count, greater_than: 0)
  end

  def update_changeset(struct, attrs), do: create_changeset(struct, attrs)
end
