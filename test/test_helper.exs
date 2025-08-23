# Start SNMP simulator for all tests using snmpkit
require Logger
Logger.info("Starting snmpkit simulator for all tests...")
:ok = FirmwareManager.SnmpKitSimHelper.start_sim()

# Register cleanup to happen after all tests
ExUnit.after_suite(fn _ ->
  Logger.info("Stopping snmpkit simulator after all tests...")
  FirmwareManager.SnmpKitSimHelper.stop_sim()
end)

# Start ExUnit with excluded tags
ExUnit.start(exclude: [:skip])

# Ensure the application is started
{:ok, _} = Application.ensure_all_started(:firmware_manager)

# Configure Ecto sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(FirmwareManager.Repo, :manual)
