#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — Deploy or update a RouterOS container over HTTP REST (no TLS) via Basic Auth
#
# Assumptions
# - RouterOS v7 REST API reachable at http://<router_ip>/rest
# - Container subsystem already enabled and configured (envlist, mounts, interface, root-dir exist if creating)
# - Operating over a trusted network (e.g., WireGuard); HTTPS is intentionally not used
#
# Defaults
NAME_DEFAULT="firmware-manager"
IMAGE_DEFAULT="ghcr.io/awksedgreep/firmware_manager:latest"
START_ON_BOOT_DEFAULT="yes"
TIMEOUT_DEFAULT=15

# Globals (populated by api())
RESP_CODE=""
RESP_BODY=""

usage() {
  cat <<EOF
Usage: $0 -i IP -u USER -p PASS [options]

Required:
  -i, --ip IP                 Router IP or host (REST base: http://IP/rest)
  -u, --user USER             API username (Basic auth)
  -p, --pass PASS             API password (Basic auth)

Optional:
  -n, --name NAME             Container name (default: ${NAME_DEFAULT})
  -r, --image REF             Image ref (default: ${IMAGE_DEFAULT})
      --envlist LIST          RouterOS env list name to attach (e.g., fm-env)
      --mounts NAMES          Comma-separated mount names to attach (e.g., fm-sqlite)
      --interface IFACE       RouterOS veth interface name for the container
      --root-dir PATH         Persistent root directory (e.g., disk1:/containers/firmware_manager/root)
      --start-on-boot yes|no  Start on boot flag (default: ${START_ON_BOOT_DEFAULT})
      --timeout SECONDS       CURL connect/total timeout (default: ${TIMEOUT_DEFAULT})
      --dry-run               Print intended actions, do not call API
  -h, --help                  Show this help

Examples:
  $0 -i 10.0.0.1 -u admin -p 'secret'
  $0 -i 10.0.0.1 -u admin -p 'secret' -n firmware-manager -r ${IMAGE_DEFAULT}
  $0 -i 10.0.0.1 -u admin -p 'secret' -n firmware-manager \
     --envlist fm-env --mounts fm-sqlite --interface fm-veth \
     --root-dir disk1:/containers/firmware_manager/root
EOF
}

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" 1>&2; }
log_err()  { printf '[ERROR] %s\n' "$*" 1>&2; }

need_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_err "Missing dependency: $1 (install it and retry)"
    exit 1
  fi
}

# api METHOD PATH [BODY_JSON]
api() {
  local method="$1"; shift
  local path="$1"; shift
  local body="${1-}"

  local url="${BASE}${path}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    local preview_body="${body}"
    # Redact password if it ever appeared (we don't embed creds in URL, but be safe)
    preview_body=${preview_body//"${PASS}"/"***REDACTED***"}
    log_info "[dry-run] ${method} ${url} body=${preview_body}"
    RESP_CODE=200
    RESP_BODY='{}'
    return 0
  fi

  local tmp_body
  tmp_body="$(mktemp)"
  trap 'rm -f "$tmp_body"' RETURN

  local curl_args=(
    -sS \
    -u "$USER:$PASS" \
    -H 'content-type: application/json' \
    --connect-timeout "$TIMEOUT" \
    -m "$TIMEOUT" \
    -X "$method" \
    "$url"
  )

  if [[ -n "${body}" ]]; then
    curl_args=("${curl_args[@]:0:${#curl_args[@]}-1}" -d "${body}" "${curl_args[-1]}")
  fi

  local http_code
  set +e
  http_code=$(curl "${curl_args[@]}" -o "$tmp_body" -w '%{http_code}')
  local curl_ec=$?
  set -e

  RESP_CODE="$http_code"
  RESP_BODY=$(cat "$tmp_body" 2>/dev/null || true)

  if [[ $curl_ec -ne 0 ]]; then
    log_err "curl failed (exit=$curl_ec) for ${method} ${path}"
    exit 1
  fi
}

# Parse args
IP=""
USER=""
PASS=""
NAME="${NAME_DEFAULT}"
IMAGE_REF="${IMAGE_DEFAULT}"
ENVLIST=""
MOUNTS=""
IFACE=""
ROOT_DIR=""
START_ON_BOOT="${START_ON_BOOT_DEFAULT}"
TIMEOUT=${TIMEOUT_DEFAULT}
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--ip) IP="$2"; shift 2;;
    -u|--user) USER="$2"; shift 2;;
    -p|--pass) PASS="$2"; shift 2;;
    -n|--name) NAME="$2"; shift 2;;
    -r|--image) IMAGE_REF="$2"; shift 2;;
    --envlist) ENVLIST="$2"; shift 2;;
    --mounts) MOUNTS="$2"; shift 2;;
    --interface) IFACE="$2"; shift 2;;
    --root-dir) ROOT_DIR="$2"; shift 2;;
    --start-on-boot) START_ON_BOOT="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) log_err "Unknown option: $1"; usage; exit 2;;
    *) break;;
  esac
done

# Validate deps
need_bin curl
need_bin jq

# Validate required
if [[ -z "$IP" || -z "$USER" || -z "$PASS" ]]; then
  log_err "Missing required flags."
  usage
  exit 2
fi

BASE="http://${IP}/rest"

if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "Dry-run: no API calls will be made. Planned actions:"
  cat <<PLAN
- Discover container by name: ${NAME}
- If exists:
    * Stop container via POST /container/stop
    * Update image via POST /container/set to ${IMAGE_REF}
    * Start container via POST /container/start
- Else (create):
    * POST /container with name=${NAME}, remote-image=${IMAGE_REF}, start-on-boot=${START_ON_BOOT}
      optional: envlist=${ENVLIST}, mounts=${MOUNTS}, interface=${IFACE}, root-dir=${ROOT_DIR}
    * Start container via POST /container/start
- Poll /container until running or timeout
PLAN
  exit 0
fi

# Helper: get container id by name
get_container_id() {
  api GET "/container"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    log_err "GET /container failed (status=${RESP_CODE}): ${RESP_BODY}"
    exit 1
  fi
  printf '%s' "$RESP_BODY" | jq -r --arg n "$NAME" '.[] | select(.name==$n) | .[".id"]' | head -n1
}

# Helper: start/stop via numbers action
stop_container_numbers() {
  local id="$1"
  local body
  body=$(jq -n --arg id "$id" '{numbers: $id}')
  api POST "/container/stop" "$body"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    log_warn "Stop failed (status=${RESP_CODE}): ${RESP_BODY}"
  fi
}

start_container_numbers() {
  local id="$1"
  local body
  body=$(jq -n --arg id "$id" '{numbers: $id}')
  api POST "/container/start" "$body"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    log_err "Start failed (status=${RESP_CODE}): ${RESP_BODY}"
    exit 1
  fi
}

set_container_image() {
  local id="$1"; local image="$2"
  local body
  body=$(jq -n --arg id "$id" --arg img "$image" '{numbers: $id, "remote-image": $img}')
  api POST "/container/set" "$body"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    return 1
  fi
  return 0
}

remove_container() {
  local id="$1"
  local body
  body=$(jq -n --arg id "$id" '{numbers: $id}')
  api POST "/container/remove" "$body"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    log_err "Remove failed (status=${RESP_CODE}): ${RESP_BODY}"
    exit 1
  fi
}

create_container() {
  local payload
  # Base object
  payload=$(jq -n --arg name "$NAME" --arg img "$IMAGE_REF" --arg sob "$START_ON_BOOT" '{name: $name, "remote-image": $img, "start-on-boot": $sob}')
  if [[ -n "$ENVLIST" ]]; then payload=$(jq -n --argjson base "$payload" --arg v "$ENVLIST" '$base + {envlist: $v}'); fi
  if [[ -n "$MOUNTS" ]]; then payload=$(jq -n --argjson base "$payload" --arg v "$MOUNTS" '$base + {mounts: $v}'); fi
  if [[ -n "$IFACE" ]]; then payload=$(jq -n --argjson base "$payload" --arg v "$IFACE" '$base + {interface: $v}'); fi
  if [[ -n "$ROOT_DIR" ]]; then payload=$(jq -n --argjson base "$payload" --arg v "$ROOT_DIR" '$base + {"root-dir": $v}'); fi

  api POST "/container" "$payload"
  if [[ ${RESP_CODE} -lt 200 || ${RESP_CODE} -ge 300 ]]; then
    log_err "Create failed (status=${RESP_CODE}): ${RESP_BODY}"
    exit 1
  fi
}

poll_running() {
  local attempts=6
  local sleep_s=5
  for ((i=1; i<=attempts; i++)); do
    local id
    id=$(get_container_id || true)
    if [[ -z "$id" || "$id" == "null" ]]; then
      sleep "$sleep_s"; continue
    fi
    # Get fresh list and record entry
    local entry
    entry=$(printf '%s' "$RESP_BODY" | jq -r --arg n "$NAME" '.[] | select(.name==$n)')
    if [[ -n "$entry" ]]; then
      local running status
      running=$(printf '%s' "$entry" | jq -r '.running // empty')
      status=$(printf '%s' "$entry" | jq -r '.status // empty')
      if [[ "$running" == "true" || "$status" == "running" ]]; then
        return 0
      fi
    fi
    sleep "$sleep_s"
  done
  return 1
}

log_info "Deploying container '${NAME}' to ${IP} with image '${IMAGE_REF}'"

# Discover existing
CID="$(get_container_id || true)"

if [[ -n "$CID" && "$CID" != "null" ]]; then
  log_info "Found existing container id=${CID} (name=${NAME}); stopping..."
  stop_container_numbers "$CID"

  log_info "Attempting in-place image update to ${IMAGE_REF} via /container/set"
  if set_container_image "$CID" "$IMAGE_REF"; then
    log_info "Image updated; starting container"
    start_container_numbers "$CID"
  else
    log_warn "In-place update unsupported or failed (status=${RESP_CODE}). Recreating entry."
    remove_container "$CID"
    log_info "Creating container entry (name=${NAME})"
    create_container
    # Refresh ID
    CID="$(get_container_id)"
    if [[ -z "$CID" || "$CID" == "null" ]]; then
      log_err "Failed to locate newly created container '${NAME}'"
      exit 1
    fi
    log_info "Starting new container id=${CID}"
    start_container_numbers "$CID"
  fi
else
  log_info "Container '${NAME}' not found; creating new entry"
  create_container
  CID="$(get_container_id)"
  if [[ -z "$CID" || "$CID" == "null" ]]; then
    log_err "Failed to locate newly created container '${NAME}'"
    exit 1
  fi
  log_info "Starting container id=${CID}"
  start_container_numbers "$CID"
fi

log_info "Polling for running state..."
if poll_running; then
  log_info "Container '${NAME}' is running with image '${IMAGE_REF}'"
  exit 0
else
  log_warn "Container '${NAME}' did not report running state before timeout"
  exit 1
fi
