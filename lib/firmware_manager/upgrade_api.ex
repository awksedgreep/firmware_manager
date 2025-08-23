defmodule FirmwareManager.UpgradeAPI do
  @moduledoc "High-level API for managing upgrade rules."

  alias FirmwareManager.UpgradeRules.Rule
  require Ash.Query

  def list_rules do
    Ash.read!(Rule)
  end

  def list_enabled_rules do
    Rule |> Ash.Query.filter(enabled: true) |> Ash.read!()
  end

  def get_rule!(id) do
    Rule |> Ash.Query.filter(id: id) |> Ash.read_one!()
  end

  def create_rule(attrs) do
    Rule |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
  end

  def update_rule(%Rule{} = rule, attrs) do
    rule |> Ash.Changeset.for_update(:update, attrs) |> Ash.update()
  end

  def delete_rule(%Rule{} = rule) do
    rule |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy()
  end
end

