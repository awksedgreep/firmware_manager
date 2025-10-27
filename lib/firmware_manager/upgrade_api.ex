defmodule FirmwareManager.UpgradeAPI do
  @moduledoc "High-level API for managing upgrade rules (Ecto)."

  import Ecto.Query
  alias FirmwareManager.Repo
  alias FirmwareManager.UpgradeRules.Rule

  def list_rules, do: Repo.all(Rule)

  def list_enabled_rules do
    from(r in Rule, where: r.enabled == true)
    |> Repo.all()
  end

  def get_rule!(id), do: Repo.get!(Rule, id)

  def create_rule(attrs) do
    %Rule{}
    |> Rule.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_rule(%Rule{} = rule, attrs) do
    rule
    |> Rule.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_rule(%Rule{} = rule), do: Repo.delete(rule)
end
