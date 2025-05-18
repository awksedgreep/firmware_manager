defmodule FirmwareManager.ModemFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FirmwareManager.Modem` context.
  """

  @doc """
  Generate a upgrade_log.
  """
  def upgrade_log_fixture(attrs \\ %{}) do
    valid_attrs = %{
      mac_address: "00:11:22:33:44:55",
      new_firmware: "some new_firmware",
      new_sysdescr: "some new_sysdescr",
      old_sysdescr: "some old_sysdescr",
      upgraded_at: ~U[2025-05-02 05:14:00Z]
    }

    {:ok, upgrade_log} =
      attrs
      |> Enum.into(valid_attrs)
      |> FirmwareManager.Modem.create_upgrade_log()

    upgrade_log
  end
end
