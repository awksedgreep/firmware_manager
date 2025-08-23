# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Project summary
- Phoenix 1.7 app using Ash 3.x and AshSqlite with LiveView UI. SQLite databases are used for dev/test. SNMP features are implemented via snmpkit for interacting with CMTS and modem devices.
- Dev server runs on http://localhost:4001 in development (see config/dev.exs).

Common commands
- Initial setup (installs deps, sets up DB, builds assets):
  - mix setup
- Start dev server (with code reloader and asset watchers):
  - mix phx.server
  - or: iex -S mix phx.server
- Compile:
  - mix compile
- Database tasks (SQLite):
  - mix ecto.setup        # create DB, run migrations, seed
  - mix ecto.reset        # drop + setup
  - mix ecto.migrate
- Ash scaffolding/data setup:
  - mix ash.setup         # sync Ash, then seeds (also run by mix setup)
- Assets:
  - mix assets.build
  - mix assets.deploy     # minify + phx.digest
- Formatting (lint-equivalent here):
  - mix format
  - mix format --check-formatted
- Tests:
  - mix test
  - mix test test/path/to/file_test.exs:LINE   # run a single test
  - mix test --only snmp                        # run only SNMP-tagged tests

Notes for running tests (SNMP simulation)
- SNMP integration tests start an in-process snmpkit simulator in test/test_helper.exs via FirmwareManager.SnmpKitSimHelper.
- Requirements on the host:
  - net-snmp CLI tools (snmpget, snmpset) available on PATH
- Tests will attempt to bind a random UDP port in the range 1161-1261 for the simulator and will print startup messages. If port conflicts occur, re-run tests.

High-level architecture
- OTP application (lib/firmware_manager/application.ex)
  - Supervision tree: Telemetry, Repo (AshSqlite), Ecto.Migrator (runs unless in release), DNSCluster, PubSub, Finch, Endpoint.
  - Note on migrations: In dev/test, migrations run at app start; in release (RELEASE_NAME set) they’re skipped—run migrations out-of-band.
- Persistence
  - AshSqlite Repo: FirmwareManager.Repo (lib/firmware_manager/repo.ex)
  - SQLite DB paths configured in config/dev.exs and config/test.exs.
  - Ecto migrations in priv/repo/migrations.
- Ash domain (lib/firmware_manager/modem.ex)
  - Domain: FirmwareManager.Modem
  - Resources (Ash.Resource, AshSqlite):
    - FirmwareManager.Modem.UpgradeLog (lib/firmware_manager/modem/upgrade_log.ex)
      - Immutable log of modem firmware upgrades. Key fields: mac_address, old/new sysDescr, new_firmware, upgraded_at.
      - API highlights (via domain functions): list_upgrade_logs/1 with pagination/sorting, get_upgrade_log!/1, create_upgrade_log/1, delete_all_upgrade_logs/0 (bulk truncate).
    - FirmwareManager.Modem.Cmts (lib/firmware_manager/modem/cmts.ex)
      - CMTS records with credentials: ip, snmp_read, modem_snmp_read, modem_snmp_write, plus optional name and timestamps.
      - Full CRUD via domain functions: list_cmts/1 (sortable/filterable), get_cmts!/1, create_cmts/1, update_cmts/2, delete_cmts/1.
- Web layer (Phoenix + LiveView)
  - Router (lib/firmware_manager_web/router.ex)
    - Browser routes: homepage, easter egg.
    - LiveViews:
      - Upgrade Logs: /upgrade_logs (Index, Show). Index performs DB aggregation for counts, supports sorting/pagination, and exposes a “Truncate Logs” action that calls Modem.delete_all_upgrade_logs/0.
      - CMTS: /cmts (Index, Show) with new/edit/delete via domain functions.
    - Dev-only routes (when :dev_routes true):
      - LiveDashboard at /dev/dashboard
      - Mailbox at /dev/mailbox
      - AshAdmin at /admin (see router guard and config/dev.exs)
  - Endpoint (lib/firmware_manager_web/endpoint.ex)
    - Bandit adapter; static files from priv/static; LiveView socket; code reloader/watchers in dev; optional Tidewave plug if available.
- SNMP integration
  - CMTS-focused module: FirmwareManager.CMTSSNMP (lib/firmware_manager/cmts_snmp.ex)
    - Discovers connected modems from a CMTS by walking specific OIDs (RFC 3636 docsIfCmtsCmStatusTable columns for MAC, status, IP). Returns list of %{mac, ip, status}.
    - get_modem/4 filters discovery by MAC.
    - Includes formatting helpers (e.g., format_uptime/1).
  - Modem-focused module: FirmwareManager.ModemSNMP (lib/firmware_manager/modem_snmp.ex)
    - Reads basic system info and DOCSIS version from a modem; checks whether SNMP-based upgrade is allowed; can initiate firmware upgrade by setting TFTP server and filename OIDs, then toggling admin status.
    - Defaults use UDP port 161; pass a different port when targeting simulators/tests.

Environments and configuration
- Dev server is configured on port 4001 (config/dev.exs). Live reload patterns exclude priv/static/uploads.
- SNMP settings are tuned to silence mib compiler warnings and define cache/dir paths in dev/test/prod config.
- Production runtime (config/runtime.exs) reads:
  - DATABASE_PATH (SQLite file path)
  - SECRET_KEY_BASE
  - PHX_SERVER (to enable server)
  - Optional DNS_CLUSTER_QUERY

Project-specific rule
- Prefer Logger for output over IO.puts/IO.inspect to control verbosity via configuration.

Files of interest
- mix.exs: dependencies, aliases (setup, ecto.setup/reset, assets.build/deploy, ash.setup), esbuild/tailwind config hooks.
- config/: environment configs for Repo/Endpoint/Ash/SNMP, plus formatter plugins.
- lib/firmware_manager/modem*.ex: Ash domain and resources; CMTS and UpgradeLog definitions.
- lib/firmware_manager/cmts_snmp.ex and lib/firmware_manager/modem_snmp.ex: SNMP integration.
- lib/firmware_manager_web/**: Router, Endpoint, LiveViews and components.
- test/support/**: DataCase, ConnCase, SnmpKitSimHelper (in-process simulator for tests).

