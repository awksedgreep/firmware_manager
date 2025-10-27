# FirmwareManager Deploy Guide (MikroTik RouterOS v7, ARM64 Container)

Deploy the manually built image from GHCR to MikroTik RouterOS Container. No CI automation assumed.

## Prerequisites
- RouterOS v7 with container feature available
- Sufficient persistent storage (e.g., `disk1:`)
- You have pushed tags to GHCR (see Build Guide)

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

## 2) Configure GHCR registry access
```bash
/container/config/set registry-url=https://ghcr.io tmpdir=disk1:/containers/tmp
# If private, set credentials (token with read:packages):
# /container/config/set registry-username=<GH_USER> registry-password=<GHCR_PAT>
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
Use the GHCR tag you pushed (latest or versioned).
```bash
/container/add name=firmware-manager \
  remote-image=ghcr.io/awksedgreep/firmware_manager:latest \
  interface=fm-veth \
  root-dir=disk1:/containers/firmware_manager/root \
  envlist=fm-env \
  mounts=fm-sqlite \
  start-on-boot=yes
```

## 7) Start and monitor
Migrations run automatically at startup via the image entrypoint.
```bash
/container/start firmware-manager
/container/print detail where name=firmware-manager
/container/logs/print follow=yes where name=firmware-manager
```
- To skip migrations (not recommended), set `SKIP_MIGRATIONS=1` in the env list.

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
/container/set firmware-manager remote-image=ghcr.io/awksedgreep/firmware_manager:<new-tag>
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
