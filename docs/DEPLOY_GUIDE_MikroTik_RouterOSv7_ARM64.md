# FirmwareManager Deploy Guide (MikroTik RouterOS v7, ARM64 Container)

Deploy the published ARM64 image to a MikroTik router using RouterOS Container. No domain/TLS; app listens on HTTP.

## Prerequisites
- RouterOS v7 with container feature available
- Sufficient persistent storage (e.g., `disk1:`)
- Internet access from the router to pull the image

## Required env/secrets (set via RouterOS env list)
- SECRET_KEY_BASE (required): output of `mix phx.gen.secret`
- DATABASE_PATH (required): `/data/firmware_manager.db`
- PHX_SERVER=true (required)
- PHX_HOST (required): set to container IP (e.g., `172.31.0.2`)
- PORT=4000 (required)
- Optional: `TZ=UTC`, `RELEASE_COOKIE=<random>` (only if clustering/remote shell is desired)

## 1) Prepare directories (persistent root and data)
```bash
/file make-dir disk1:/containers/firmware_manager/root
/file make-dir disk1:/containers/firmware_manager/data
/file print where name~"containers/firmware_manager"
```

## 2) Configure container registry (GHCR)
```bash
/container/config/set registry-url=https://ghcr.io tmpdir=disk1:/containers/tmp
# If the image is private, set credentials (Package: read token):
# /container/config/set registry-username=mcotner registry-password=YOUR_GHCR_TOKEN
```
- Alternative (Docker Hub public):
```bash
/container/config/set registry-url=https://registry-1.docker.io tmpdir=disk1:/containers/tmp
```

Visibility/auth notes
- Public GHCR package: no credentials needed on RouterOS.
- Private GHCR package: create a PAT with read:packages; for org packages, enable SSO on the token. Configure on RouterOS with:
  - /container/config set registry-username=<user-or-bot> registry-password=<PAT>

Secure-ish one-liner (sets vars, applies, then erases token):
```bash
/system/script/environment add name=GHCR_USER value="mcotner"; \
/system/script/environment add name=GHCR_TOKEN value="PASTE_GHCR_PAT_HERE"; \
/container/config/set registry-url=https://ghcr.io tmpdir=disk1:/containers/tmp registry-username=$GHCR_USER registry-password=$GHCR_TOKEN; \
/system/script/environment remove [find name=GHCR_TOKEN]
```

## 3) Networking: veth + IPs
Give the container its own L3 address on a private /24.
```bash
/interface/veth/add name=fm-veth address=172.31.0.2/24 gateway=172.31.0.1
/ip/address/add address=172.31.0.1/24 interface=fm-veth comment="firmware_manager gateway"
```

## 4) Persistent mount for SQLite
```bash
/container/mounts/add name=fm-sqlite src=disk1:/containers/firmware_manager/data dst=/data
/container/mounts/print
```

## 5) Environment variables (create list with required secrets)
Paste your generated SECRET_KEY_BASE.
```bash
/container/envs/add list=fm-env name=PHX_SERVER value=true
/container/envs/add list=fm-env name=SECRET_KEY_BASE value=PASTE_YOUR_SECRET_KEY_BASE_HERE
/container/envs/add list=fm-env name=DATABASE_PATH value=/data/firmware_manager.db
/container/envs/add list=fm-env name=PHX_HOST value=172.31.0.2
/container/envs/add list=fm-env name=PORT value=4000
# Optional
/container/envs/add list=fm-env name=TZ value=UTC
/container/envs/print where list=fm-env
```

## 6) Add the container
Replace the image with the one you pushed (from the Build Guide).
```bash
/container/add name=firmware-manager \
  remote-image=ghcr.io/mcotner/firmware_manager:v0.1.1 \
  interface=fm-veth \
  root-dir=disk1:/containers/firmware_manager/root \
  envlist=fm-env \
  mounts=fm-sqlite \
  start-on-boot=yes
```

## 7) First start with migrations
Use the image entrypoint’s migration hook by setting `MIGRATE=1` for the first run.
```bash
# add MIGRATE=1
a:= [/container/envs/add list=fm-env name=MIGRATE value=1]

# start and monitor
/container/start firmware-manager
/container/print detail where name=firmware-manager
/container/logs/print follow=yes where name=firmware-manager
```
After a successful start (migrations applied), remove MIGRATE and restart normally:
```bash
/container/stop firmware-manager
/container/envs/remove [find where list=fm-env name=MIGRATE]
/container/start firmware-manager
```

## 8) Verify service
- From router:
```bash
/tool/fetch url="http://172.31.0.2:4000/" output=none
```
- From LAN host: open `http://172.31.0.2:4000`

Optional WAN exposure (adjust interface lists/rules as needed):
```bash
/ip/firewall/nat/add chain=dstnat in-interface-list=WAN protocol=tcp dst-port=4000 action=dst-nat to-addresses=172.31.0.2 to-ports=4000 comment="firmware_manager http"
/ip/firewall/filter/add chain=forward dst-address=172.31.0.2 protocol=tcp dst-port=4000 action=accept place-before=0 comment="allow firmware_manager http"
```

## 9) Updates
Pull a new version and restart:
```bash
/container/stop firmware-manager
/container/set firmware-manager remote-image=ghcr.io/mcotner/firmware_manager:v0.1.2
/container/start firmware-manager
```
Persistent data is preserved because the SQLite DB lives on `fm-sqlite` (disk1:/containers/firmware_manager/data).

## 10) Troubleshooting
```bash
/container/logs/print follow=yes where name=firmware-manager
/container/envs/print where list=fm-env
/container/mounts/print where name=fm-sqlite
```
Common checks:
- SECRET_KEY_BASE present/non-empty
- DATABASE_PATH points to `/data/firmware_manager.db` and volume is writable
- PHX_HOST set to the IP you’re using in the browser (affects generated URLs)
- Port 4000 reachable; add firewall rules if needed
