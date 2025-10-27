# FirmwareManager Build Guide (MikroTik RouterOS Container, ARM64)

This guide builds and publishes an ARM64 container image suitable for MikroTik RouterOS v7 Container.

## Prerequisites
- Docker with Buildx enabled
- Access to GitHub Container Registry (GHCR)
- Repo contains a Dockerfile ready for ARM64 and release builds

## Required production env/secrets
- SECRET_KEY_BASE (required): Phoenix signing/encryption secret
- DATABASE_PATH (required): path to SQLite db inside the container; default image uses `/data/firmware_manager.db`
- PHX_SERVER=true (required): enables server in release
- PORT (required): HTTP port (default 4000 in the image)
- PHX_HOST (required): host/IP clients will use (use container IP on MikroTik, e.g., 172.31.0.2)
- Optional: TZ (e.g., `UTC`), RELEASE_COOKIE (only for clustering/remote shell)

Generate SECRET_KEY_BASE locally:
```bash
mix phx.gen.secret
```

## Image coordinates and Buildx setup
```bash
# Choose your GHCR coordinates
export REGISTRY=ghcr.io
export IMAGE_OWNER=mcotner               # GitHub user or org that will own the package
export IMAGE_NAME=firmware_manager
export IMAGE_TAG=v0.1.1
export IMAGE_REF="$REGISTRY/$IMAGE_OWNER/$IMAGE_NAME:$IMAGE_TAG"

# ensure buildx is available
docker buildx ls >/dev/null 2>&1 || docker buildx create --use
```

## Build and push ARM64 image
```bash
# Login to GHCR (set GHCR_PAT in your environment; do not echo it)
export GHCR_USER="$IMAGE_OWNER"
printf '%s' "$GHCR_PAT" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# build+push for ARM64 (linux/arm64/v8)
docker buildx build \
  --platform linux/arm64/v8 \
  -t "$IMAGE_REF" \
  --push \
  .
```

## GHCR package visibility and minimal permissions
- Public image (Web UI): In GitHub, go to Packages > firmware_manager > Package settings and set Visibility to Public.
- Public image (CLI): using gh and the REST API
```bash
# For a user-owned package
gh api -X PATCH -H "Accept: application/vnd.github+json" \
  /user/packages/container/firmware_manager/visibility \
  -f visibility=public

# For an org-owned package
ORG=your-org
gh api -X PATCH -H "Accept: application/vnd.github+json" \
  /orgs/$ORG/packages/container/firmware_manager/visibility \
  -f visibility=public
```
- Private image: Use a GitHub Personal Access Token (classic) with scopes:
  - write:packages (push)
  - read:packages (pull)
  - delete:packages (optional)
  - For org packages, ensure SSO is enabled for the token.
- The token is used only for docker login; do not print it. Keep it in GHCR_PAT env.

Notes
- The existing Dockerfile produces a small ARM64 image with a Phoenix release.
- The runtime expects `/data` to be a writable volume and defaults `DATABASE_PATH` to `/data/firmware_manager.db`.
- Use `MIGRATE=1` on first start to run database migrations automatically via the included entrypoint script.

## Optional: Local smoke test
```bash
mkdir -p .container/data

docker run --rm \
  -e PHX_SERVER=true \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=127.0.0.1 \
  -e PORT=4000 \
  -e DATABASE_PATH=/data/firmware_manager.db \
  -e MIGRATE=1 \
  -p 4000:4000 \
  -v "$PWD/.container/data:/data" \
  "$IMAGE_REF"

# new terminal
curl -i http://127.0.0.1:4000/
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
