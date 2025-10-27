#!/bin/sh
set -eu

# Ensure data dir exists (for SQLite db path)
mkdir -p /data

# Optional: run migrations when MIGRATE=1
if [ "${MIGRATE:-0}" = "1" ]; then
  /app/bin/firmware_manager eval "Elixir.Ecto.Migrator.with_repo(Elixir.FirmwareManager.Repo, &Elixir.Ecto.Migrator.run(&1, :up, all: true))"
fi

# Start the release
exec /app/bin/firmware_manager start
