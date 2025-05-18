# SNMPSIM Test Environment for Firmware Manager

This directory contains a complete SNMPSIM test environment for testing the Firmware Manager's SNMP functionality, including both Cable Modem (CM) and Cable Modem Termination System (CMTS) simulation.

## Prerequisites

- Podman
- net-snmp (for snmpget/snmpset commands)
- jq (for processing JSON output in examples)

## Quick Start

1. Make the start script executable:
   ```bash
   chmod +x start_snmpsim.sh
   ```

2. Start the SNMPSIM container:
   ```bash
   ./start_snmpsim.sh
   ```

3. Test basic SNMP GET:
   ```bash
   snmpget -v2c -c public 127.0.0.1 1.3.6.1.2.1.1.1.0
   ```

4. Test CMTS functionality (list all connected modems):
   ```bash
   # Get list of modem MAC addresses
   snmptable -v2c -c public -Ci 127.0.0.1 1.3.6.1.2.1.10.127.1.3.3.1.2
   
   # Get IP addresses of all modems
   snmptable -v2c -c public -Ci 127.0.0.1 1.3.6.1.2.1.10.127.1.3.3.1.4
   
   # Get status of all modems (8 = online, 9 = offline)
   snmptable -v2c -c public -Ci 127.0.0.1 1.3.6.1.2.1.10.127.1.3.3.1.6
   ```

5. Test SNMP SET (using the read-write community):
   ```bash
   # Set TFTP server on a modem
   snmpset -v2c -c private 127.0.0.1 1.3.6.1.2.1.69.1.3.3.0 s "192.168.1.100"
   ```

6. View logs:
   ```bash
   podman logs -f snmpsim
   ```

## Configuration Files

- `data/public.snmprec`: SNMP record file with DOCSIS OIDs for both CM and CMTS
- `data/snmpd.conf`: SNMP daemon configuration

## Simulated Network

The simulator includes:

### CMTS (Cable Modem Termination System)
- System name: `test-cmts-1`
- Contact: `noc@example.com`
- Location: `Test Lab - CMTS`

### Connected Modems
1. **Modem 1**
   - MAC: `00:11:22:33:44:55`
   - IP: `192.168.1.10`
   - Status: Online (8)
   - Uptime: 1 hour

2. **Modem 2**
   - MAC: `00:11:22:33:44:56`
   - IP: `192.168.1.11`
   - Status: Online (8)
   - Uptime: 30 minutes

## Community Strings

- Read-only: `public`
- Read-write: `private`

## Container Management

- Start: `podman start snmpsim`
- Stop: `podman stop snmpsim`
- Remove: `podman rm snmpsim`
- View logs: `podman logs -f snmpsim`

## Testing with Elixir

### Testing CMTS Functions

```elixir
test "get list of modems from CMTS" do
  # Start the SNMPSIM container if not already running
  System.cmd("test/fixtures/snmpsim/start_snmpsim.sh", [])
  
  # Example function to get all connected modems
  modems = FirmwareManager.CMTS.get_connected_modems("127.0.0.1", "public", 161)
  
  assert length(modems) == 2
  assert %{ip: "192.168.1.10", status: :online} in modems
  assert %{ip: "192.168.1.11", status: :online} in modems
end
```

### Testing Modem Functions

```elixir
test "get modem info from SNMPSIM" do
  # Test against the first simulated modem
  {:ok, info} = FirmwareManager.ModemSNMP.get_modem_info("192.168.1.10", "public", 161)
  assert info.system_name =~ "Cable Modem"
  
  # Test firmware upgrade
  assert :ok = FirmwareManager.ModemSNMP.upgrade_firmware(
    "192.168.1.10", 
    "private", 
    "tftp.example.com", 
    "firmware.bin"
  )
end
```

### Example CMTS Module

You might implement a CMTS module like this:

```elixir
defmodule FirmwareManager.CMTS do
  @moduledoc """
  Functions for interacting with CMTS devices.
  """
  
  @doc """
  Get all connected modems from CMTS.
  """
  def get_connected_modems(ip, community, port \\ 161) do
    with {:ok, credential} <- SNMP.credential(%{version: :v2c, community: community}),
         uri = URI.parse("snmp://#{ip}:#{port}") do
      
      # Get all rows from docsIfCmtsCmStatusTable
      base_oid = [1, 3, 6, 1, 2, 1, 10, 127, 1, 3, 3, 1]
      
      # Get MAC addresses, IPs, and status for all modems
      varbinds = [
        %{oid: base_oid ++ [2]},  # MAC addresses
        %{oid: base_oid ++ [4]},  # IP addresses
        %{oid: base_oid ++ [6]}   # Status values
      ]
      
      case SNMP.request(%{uri: uri, credential: credential, varbinds: varbinds}) do
        {:ok, [macs, ips, statuses]} ->
          # Process the results into a list of modem maps
          process_modem_list(macs, ips, statuses)
          
        error ->
          error
      end
    end
  end
  
  defp process_modem_list(macs, ips, statuses) do
    # Implementation to process the SNMP response
    # into a list of %{mac: mac, ip: ip, status: status} maps
  end
end
```

## Troubleshooting

1. If you get permission errors, try running with `sudo` or configure podman to run rootless.
2. If port 161 is in use, you can change the port in `start_snmpsim.sh` and your test code.
3. Check container logs with `podman logs snmpsim` for any issues.

## Cleaning Up

To stop and remove the container:

```bash
podman stop snmpsim
podman rm snmpsim
```

To remove the persistent volume:

```bash
podman volume rm snmpsim-data
```
