#!/bin/sh
set -eu

# Ensure data dir exists (for SQLite db path)
mkdir -p /data

# By default, run migrations before starting the app; opt out with SKIP_MIGRATIONS=1
if [ "${SKIP_MIGRATIONS:-0}" != "1" ]; then
  echo "[entrypoint] Running database migrations..."
  /app/bin/firmware_manager eval "Elixir.Ecto.Migrator.with_repo(Elixir.FirmwareManager.Repo, &Elixir.Ecto.Migrator.run(&1, :up, all: true))"
  echo "[entrypoint] Database migrations completed."
else
  echo "[entrypoint] Skipping database migrations (SKIP_MIGRATIONS=1)."
fi

# Start the release
exec /app/bin/firmware_manager start
