# Start SNMP simulator for all tests
IO.puts("Starting SNMPSIM for all tests...")
:ok = FirmwareManager.SNMPSimHelper.start_snmpsim()

# Register cleanup to happen after all tests
ExUnit.after_suite(fn _ ->
  IO.puts("Stopping SNMPSIM after all tests...")
  FirmwareManager.SNMPSimHelper.stop_snmpsim()
end)

# Start ExUnit with excluded tags
ExUnit.start(exclude: [:skip])

# Ensure the application is started
{:ok, _} = Application.ensure_all_started(:firmware_manager)

# Configure Ecto sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(FirmwareManager.Repo, :manual)
