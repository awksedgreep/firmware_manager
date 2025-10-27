# FirmwareManager

A Phoenix 1.7 app with Ash + SQLite and SNMP tooling.

## Development (local)
- mix setup
- mix phx.server (or: iex -S mix phx.server)
- Visit http://localhost:4001

## Containers (local build and run)
Build a multi-stage image locally and run it. Migrations run automatically on startup.
```bash
export IMAGE_REF=localhost/firmware_manager:latest
podman build -t "$IMAGE_REF" .

SECRET_KEY_BASE=$(openssl rand -hex 64)
podman run --rm --name firmware-manager \
  -p 4000:4000 \
  -v fm_data:/data \
  -e SECRET_KEY_BASE \
  -e DATABASE_PATH=/data/firmware_manager.db \
  "$IMAGE_REF"
```
Notes
- To skip migrations on a particular run: add -e SKIP_MIGRATIONS=1
- Default PORT inside the container is 4000

## Deployment (MikroTik RouterOS v7 Container)
- Build and tag locally, optionally push to GHCR: ghcr.io/awksedgreep/firmware_manager:{latest,vX.Y.Z}
- On RouterOS, configure registry ghcr.io, create env list with:
  - PHX_SERVER=true
  - SECRET_KEY_BASE=<mix phx.gen.secret>
  - DATABASE_PATH=/data/firmware_manager.db
  - PHX_HOST=<container IP, e.g., 172.31.0.2>
  - PORT=4000
- Add the container with remote-image=ghcr.io/awksedgreep/firmware_manager:latest and mount /data
- Migrations run automatically at startup; logs available via /container/logs

## Detailed guides
- Build guide: docs/BUILD_GUIDE_MikroTik_ARM64.md
- Deploy guide: docs/DEPLOY_GUIDE_MikroTik_RouterOSv7_ARM64.md

## Learn more (Phoenix)
- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
