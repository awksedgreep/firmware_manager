# FirmwareManager Build Guide (Local multi-stage with Podman + manual GHCR push)

Build the ARM64 release image locally with Podman and (optionally) push to GHCR manually. No CI/buildx automation.

## Prerequisites
- Podman
- A GitHub Personal Access Token with read:packages, write:packages (for pushing)

## Version/tag setup
```bash
export OWNER=awksedgreep              # change if needed
export IMAGE=firmware_manager
export VERSION=v0.1.1                 # bump per release
export LOCAL_REF=localhost/$IMAGE:latest
export GHCR_LATEST=ghcr.io/$OWNER/$IMAGE:latest
export GHCR_VERSION=ghcr.io/$OWNER/$IMAGE:$VERSION
```

## Build (multi-stage, locally)
```bash
podman build \
  -t "$LOCAL_REF" \
  -t "$GHCR_LATEST" \
  -t "$GHCR_VERSION" \
  .
```

## Optional: push to GHCR (manual, not automated)
```bash
# Login without exposing the token
echo "$GHCR_PAT" | podman login ghcr.io -u "$OWNER" --password-stdin

# Push tags
podman push "$GHCR_VERSION"
podman push "$GHCR_LATEST"
```

## Local run (migrations auto-run on start)
```bash
export SECRET_KEY_BASE=$(openssl rand -hex 64)
podman run --rm --name firmware-manager \
  -p 4000:4000 \
  -v fm_data:/data \
  -e SECRET_KEY_BASE \
  -e DATABASE_PATH=/data/firmware_manager.db \
  "$LOCAL_REF"
```
- The entrypoint runs Ecto migrations by default; set `-e SKIP_MIGRATIONS=1` to skip.

## Verify
```bash
podman logs -f firmware-manager
curl -fsS http://127.0.0.1:4000/ | head -c 200
```

## Suggested .dockerignore
```gitignore
/_build
/deps
/priv/static/assets
/priv/static/cache_manifest.json
/node_modules
/assets/node_modules
/.git
/.DS_Store
```
