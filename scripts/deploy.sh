#!/usr/bin/env bash
# Unified, idempotent deployment for victron-ble2mqtt-integration
# - Verifies and installs prerequisites (Docker, Compose, BlueZ, Mosquitto)
# - Installs Dockge + /opt/stacks wrappers; removes legacy systemd compose runners
# - Builds image and starts victron / homeassistant / Watchtower via Compose (restart policies survive reboot)
# - Optional extras via env: ENABLE_PERF_TUNING=1, ENABLE_DOCKGE=1, ENABLE_TOOLS=1, ENABLE_AUTOHEAL=1 (default),
#   ENABLE_FAILOVER_MONITOR=1, ENABLE_SUNGOLD=0, ENABLE_HA_MQTT_INTEGRATION=1
#   FORCE_HA_MQTT_YAML is deprecated (HA 2026+ rejects YAML broker settings).
# - TrueNAS hub (LAN): ENABLE_DOCKER_REGISTRY_MIRROR=1 (default) merges registry-mirrors http://192.168.0.111:5000 into /etc/docker/daemon.json;
#   nfs /mnt/cluster/wheels/victron enables PIP_OFFLINE=1 victron image builds and optional HA tarball docker load.
#   ENABLE_HOME_ASSISTANT=0 skips Home Assistant compose (use when hub has no HA tarball and you must avoid GHCR).
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[deploy] Git $(git rev-parse --short HEAD 2>/dev/null) branch $(git branch --show-current 2>/dev/null || echo detached)"
fi

# --- trap for helpful errors ---
trap 'rc=$?; echo "[deploy] Failed at line $LINENO (exit=$rc)" >&2; exit $rc' ERR

# --- ensure .env exists for MQTT_* (Mosquitto auth, HA MQTT integration, redeploy_victron.sh) ---
ensure_dotenv_for_mqtt() {
  local touched=false
  if [[ ! -f ./.env ]]; then
    if [[ -f ./dotenv.sample ]]; then
      echo "[deploy] Creating .env from dotenv.sample (set MQTT_USER / MQTT_PASSWORD, then re-run deploy if Mosquitto already configured)."
      cp ./dotenv.sample ./.env
    elif [[ -f ./.env.sample ]]; then
      echo "[deploy] Creating .env from .env.sample (set MQTT_USER / MQTT_PASSWORD, then re-run deploy if Mosquitto already configured)."
      cp ./.env.sample ./.env
    else
      echo "[deploy] Creating .env with MQTT placeholders (dotenv.sample missing from checkout)."
      cat > ./.env <<'EOS'
# MQTT broker settings for Mosquitto, Home Assistant, and the victron_ble2mqtt container.
# Use the Pi's real LAN IP (from `hostname -I`) instead of localhost/127.0.0.1 for reliable connectivity.
# The new deploy verification will fail loudly if Mosquitto cannot bind port 1883 or auth fails.
MQTT_HOST=192.168.0.XX
MQTT_PORT=1883
MQTT_USER=victron
MQTT_PASSWORD=your_secure_password_here
EOS
    fi
    touched=true
  elif ! grep -qE '^[[:space:]]*MQTT_USER=' ./.env 2>/dev/null; then
    echo "[deploy] Appending MQTT_* placeholders to .env (set MQTT_USER / MQTT_PASSWORD)."
    {
      echo ""
      echo "# MQTT — Home Assistant + victron (added by deploy.sh)"
      echo "MQTT_HOST=127.0.0.1"
      echo "MQTT_PORT=1883"
      echo "MQTT_USER="
      echo "MQTT_PASSWORD="
    } >> ./.env
    touched=true
  fi
  if [[ "$touched" == true ]]; then
    chmod 600 ./.env 2>/dev/null || true
  fi
}
ensure_dotenv_for_mqtt

# --- load env if present ---
if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

# Force a real LAN IP for MQTT_HOST if it is still localhost/127.0.0.1.
# This is critical for the container to reach the broker when using network_mode: host.
if [[ "${MQTT_HOST:-}" == "localhost" || "${MQTT_HOST:-}" == "127.0.0.1" || -z "${MQTT_HOST:-}" ]]; then
  LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '')"
  if [[ -n "$LAN_IP" && "$LAN_IP" != "127.0.0.1" ]]; then
    echo "[deploy] Setting MQTT_HOST=${LAN_IP} in .env (Pi LAN IP). Edit .env to change."
    sed -i "s/^MQTT_HOST=.*/MQTT_HOST=${LAN_IP}/" ./.env 2>/dev/null || echo "MQTT_HOST=${LAN_IP}" >> ./.env
    MQTT_HOST="$LAN_IP"
  fi
fi

: "${MQTT_HOST:=127.0.0.1}"
: "${MQTT_PORT:=1883}"
: "${FORCE_HA_MQTT_YAML:=0}"
: "${ENABLE_HA_MQTT_INTEGRATION:=1}"
: "${ENABLE_HA_WATCHDOG:=0}"
: "${ENABLE_HOME_ASSISTANT:=1}"
: "${ENABLE_DOCKGE:=1}"
: "${ENABLE_TOOLS:=1}"
: "${ENABLE_AUTOHEAL:=1}"
: "${ENABLE_VSCODE_CLEANUP:=1}"
: "${ENABLE_UNATTENDED_UPGRADES:=0}"
: "${ENABLE_DOCKER_PRUNE:=1}"
: "${ENABLE_MQTT_WATCHDOG:=1}"
: "${ENABLE_SUNGOLD:=0}"
: "${ENABLE_DOCKER_REGISTRY_MIRROR:=1}"
: "${DOCKER_REGISTRY_MIRROR:=http://192.168.0.111:5000}"
: "${TRUENAS_IP:=192.168.0.111}"
: "${ENSURE_TRUENAS_NFS_MOUNT:=1}"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

victron_hub_wheel_dir() {
  echo "${CLUSTER_WHEELS_VICTRON:-/mnt/cluster/wheels/victron}"
}

victron_hub_has_wheels() {
  local dir f
  dir="$(victron_hub_wheel_dir)"
  [[ -d "$dir" ]] || return 1
  f="$(find "$dir" -maxdepth 1 -type f -name '*.whl' -print -quit 2>/dev/null || true)"
  [[ -n "$f" ]]
}

maybe_mount_truenas_hub_for_victron() {
  [[ "${ENSURE_TRUENAS_NFS_MOUNT:-1}" != "1" ]] && return 0
  if victron_hub_has_wheels; then
    return 0
  fi
  if mountpoint -q /mnt/cluster 2>/dev/null; then
    local hd
    hd="$(victron_hub_wheel_dir)"
    if [[ ! -d "$hd" ]]; then
      echo "[deploy] /mnt/cluster mounted but hub directory is missing: $hd"
    else
      echo "[deploy] /mnt/cluster mounted; $hd exists but has no .whl files yet."
    fi
    echo "[deploy] On TrueNAS (.111), seed once: sudo bash /mnt/HDDs/Alfa-AI/repo/alfa-ai/scripts/seed-victron-wheels-truenas.sh"
    return 0
  fi
  if ! ping -c 1 -W 2 "${TRUENAS_IP:-192.168.0.111}" >/dev/null 2>&1; then
    echo "[deploy] TrueNAS ${TRUENAS_IP:-192.168.0.111} unreachable — skip NFS mount (PyPI / GHCR fallback)."
    return 0
  fi
  echo "[deploy] Victron hub wheels not visible — mounting TrueNAS NFS at /mnt/cluster ..."
  if ! TRUENAS_IP="${TRUENAS_IP:-192.168.0.111}" bash "$ROOT_DIR/scripts/mount-truenas-hub.sh"; then
    echo "[deploy] WARN: mount-truenas-hub.sh failed — hub offline path unavailable." >&2
    echo "[deploy] Manual: sudo bash scripts/mount-truenas-hub.sh  (see docs/ALFA_CLUSTER_INTEGRATION.md)" >&2
    return 0
  fi
  if ! victron_hub_has_wheels; then
    echo "[deploy] NFS mounted; populate $(victron_hub_wheel_dir) on .111: seed-victron-wheels-truenas.sh"
  fi
}

ensure_victron_hub_wheel_dir_on_cluster() {
  local hd parent
  hd="$(victron_hub_wheel_dir)"
  parent="$(dirname "$hd")"
  if ! mountpoint -q /mnt/cluster 2>/dev/null; then
    return 0
  fi
  if [[ ! -d "$parent" ]]; then
    echo "[deploy] WARN: /mnt/cluster mounted but $parent missing — fix hub layout on TrueNAS." >&2
    return 0
  fi
  if [[ ! -d "$hd" ]]; then
    echo "[deploy] Creating NFS directory $hd ..."
    if sudo mkdir -p "$hd"; then
      echo "[deploy] Created $hd (still empty until seed-victron-wheels-truenas.sh runs on .111)."
    else
      echo "[deploy] WARN: could not create $hd — check NFS write permissions." >&2
    fi
  fi
}

prepare_victron_docker_build_env() {
  mkdir -p "$ROOT_DIR/wheels"
  export PIP_OFFLINE="${PIP_OFFLINE:-0}"
  local hub_dir
  hub_dir="$(victron_hub_wheel_dir)"
  if [[ -d "$hub_dir" ]]; then
    echo "[deploy] Syncing pip wheels from TrueNAS hub ($hub_dir) ..."
    CLUSTER_WHEELS_VICTRON="$hub_dir" bash "$ROOT_DIR/scripts/sync-victron-wheels-from-hub.sh" || true
  else
    echo "[deploy] Hub wheels path $hub_dir not present — pip uses PyPI when PIP_OFFLINE=0."
  fi
  local whl_count
  whl_count="$(find "$ROOT_DIR/wheels" -maxdepth 1 -type f -name '*.whl' 2>/dev/null | wc -l)"
  whl_count="${whl_count// /}"
  if [[ "${whl_count:-0}" -gt 0 ]]; then
    export PIP_OFFLINE=1
    echo "[deploy] Victron image build: PIP_OFFLINE=1 (${whl_count} wheels in ./wheels)."
  else
    export PIP_OFFLINE=0
    echo "[deploy] Victron image build: PIP_OFFLINE=0 (no wheels in ./wheels)."
  fi
}

load_hub_image_if_needed() {
  local img="$1" tarball_name="$2" label="$3"
  if docker image inspect "$img" >/dev/null 2>&1; then
    return 0
  fi
  local tb
  for tb in \
    "/mnt/cluster/docker-images/${tarball_name}" \
    "/mnt/cluster/docker/images/${tarball_name}"; do
    [[ ! -f "$tb" ]] && continue
    echo "[deploy] Loading ${label} image from hub tarball: $tb"
    docker load <"$tb"
    return 0
  done
  echo "[deploy] No ${label} tarball on hub (${tarball_name}) — compose may pull from the internet."
  echo "[deploy] Seed on .111: sudo bash /mnt/HDDs/Alfa-AI/repo/alfa-ai/scripts/seed-victron-wheels-truenas.sh"
  return 0
}

# Pinned HA tag (Compose default). Override with HA_IMAGE=... in .env.
# Official pin pattern: https://www.home-assistant.io/common-tasks/container/
HA_IMAGE="${HA_IMAGE:-ghcr.io/home-assistant/home-assistant:2026.7.3}"
export HA_IMAGE
HA_IMAGE_STABLE_ALIAS="ghcr.io/home-assistant/home-assistant:stable"

ensure_ha_image() {
  if docker image inspect "$HA_IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  load_hub_image_if_needed "$HA_IMAGE" \
    "home-assistant-2026.7.3.tar.gz" "Home Assistant"
  if docker image inspect "$HA_IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  # Legacy hub filename loads as :stable — retag so Compose pin resolves.
  load_hub_image_if_needed "$HA_IMAGE_STABLE_ALIAS" \
    "home-assistant-stable.tar.gz" "Home Assistant (legacy tarball name)"
  if docker image inspect "$HA_IMAGE_STABLE_ALIAS" >/dev/null 2>&1; then
    echo "[deploy] Retagging ${HA_IMAGE_STABLE_ALIAS} -> ${HA_IMAGE} for Compose pin"
    docker tag "$HA_IMAGE_STABLE_ALIAS" "$HA_IMAGE" || true
  fi
}

load_all_hub_images() {
  ensure_ha_image
  load_hub_image_if_needed "louislam/dockge:1" \
    "dockge-1.tar.gz" "Dockge"
  load_hub_image_if_needed "containrrr/watchtower:1.7.1" \
    "watchtower-1.7.1.tar.gz" "Watchtower"
}

apt_install() {
  local pkgs=("$@")
  if ! need_cmd apt-get; then
    echo "[deploy] apt-get not available; install ${pkgs[*]} manually." >&2
    return 1
  fi
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

ensure_group_member() {
  local user="$1" group="$2"
  if ! id -nG "$user" | grep -qw "$group"; then
    echo "[deploy] Adding $user to $group group..."
    sudo usermod -aG "$group" "$user" || true
    echo "[deploy] New group membership requires a new login shell. Re-run after 'newgrp $group' if needed."
  fi
}

ensure_service_active() {
  local svc="$1"
  sudo systemctl enable --now "$svc" 2>/dev/null || sudo systemctl restart "$svc" 2>/dev/null || true
}

# Mosquitto: do not swallow start failures (ensure_service_active alone can hide a broken config).
mosquitto_restart_and_verify() {
  echo "[deploy] Restarting and verifying Mosquitto (listener on port ${MQTT_PORT} + auth)..."

  # Use || true so set -e does not kill the script before we can print diagnostics.
  if ! sudo systemctl restart mosquitto; then
    echo "[deploy] ERROR: mosquitto.service failed to restart. Config or unit problem." >&2
    echo "--- systemctl status mosquitto ---" >&2
    sudo systemctl --no-pager -l status mosquitto >&2 || true
    echo "--- journalctl -u mosquitto (last 80 lines) ---" >&2
    sudo journalctl -u mosquitto -n 80 --no-pager >&2 || true
    echo "--- /etc/mosquitto/mosquitto.conf ---" >&2
    sudo cat /etc/mosquitto/mosquitto.conf >&2 || true
    echo "--- /etc/mosquitto/conf.d/ ---" >&2
    sudo ls -la /etc/mosquitto/conf.d/ >&2 || true
    for f in /etc/mosquitto/conf.d/*.conf; do
      [[ -f "$f" ]] || continue
      echo "--- $f ---" >&2
      sudo cat "$f" >&2 || true
    done
    exit 1
  fi
  sleep 2

  if ! systemctl is-active --quiet mosquitto; then
    echo "[deploy] ERROR: mosquitto.service is not active after restart." >&2
    sudo journalctl -u mosquitto -n 80 --no-pager >&2 || true
    exit 1
  fi

  # Check that something is actually listening on the MQTT port.
  if ! ss -lntp 2>/dev/null | grep -qE ":${MQTT_PORT}\b"; then
    echo "[deploy] ERROR: no listener on TCP port ${MQTT_PORT}." >&2
    echo "--- ss -lntp (all listeners) ---" >&2
    ss -lntp >&2 || true
    sudo journalctl -u mosquitto -n 40 --no-pager >&2 || true
    exit 1
  fi

  local sub_args=("-h" "127.0.0.1" "-p" "${MQTT_PORT}" "-t" '$SYS/broker/uptime' "-C" "1" "-W" "10")
  if [[ -n "${MQTT_USER:-}" && -n "${MQTT_PASSWORD:-}" ]]; then
    sub_args+=("-u" "$MQTT_USER" "-P" "$MQTT_PASSWORD")
  fi
  if ! mosquitto_sub "${sub_args[@]}" >/dev/null 2>&1; then
    echo "[deploy] ERROR: subscribe test failed (wrong credentials or broker not ready)." >&2
    sudo journalctl -u mosquitto -n 30 --no-pager >&2 || true
    exit 1
  fi
  echo "[deploy] Mosquitto OK (listening on ${MQTT_PORT}, subscribe test passed)."
}

render_unit_with_user_path() {
  local src="$1" dst="$2"
  local user="${SUDO_USER:-$USER}"
  local home
  home="$(getent passwd "$user" | awk -F: '{print $6}')"
  if [[ -z "$home" ]]; then home="$HOME"; fi
  mkdir -p "$(dirname "$dst")"
  sed -e "s#/home/user1#$home#g" \
      -e "s#User=user1#User=$user#g" \
      -e "s#Group=user1#Group=$user#g" \
      "$src" | sudo tee "$dst" >/dev/null
}

# Legacy victron-ble2mqtt.service / victron-tools.service managed stacks; Dockge + Compose restart policies replace these.
cleanup_legacy_systemd_runners() {
  echo "[deploy] Removing legacy systemd compose runners (stacks run via Compose + Dockge) ..."
  sudo systemctl disable --now victron-ble2mqtt.service 2>/dev/null || true
  sudo systemctl disable --now victron-tools.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/victron-ble2mqtt.service
  sudo rm -f /etc/systemd/system/victron-tools.service
  sudo systemctl daemon-reload || true
}

# Compose paths inside included files resolve relative to the included file's directory (repo root).
write_dockge_stack_wrapper() {
  local stack_name="$1"
  local included_compose="$2"
  sudo mkdir -p "/opt/stacks/${stack_name}"
  sudo tee "/opt/stacks/${stack_name}/compose.yaml" >/dev/null <<EOF
## Generated by scripts/deploy.sh — re-run deploy after editing compose in the repo.
include:
  - path: ${included_compose}
EOF
}

install_sungold_udev_rule() {
  if [[ ! -f "$ROOT_DIR/udev/99-sungold-ch340.rules" ]]; then
    echo "[deploy] WARN: udev/99-sungold-ch340.rules missing — skip Sungold udev install." >&2
    return 0
  fi
  echo "[deploy] Installing Sungold CH340 udev rule (/dev/sungold) ..."
  sudo install -m 0644 -D "$ROOT_DIR/udev/99-sungold-ch340.rules" /etc/udev/rules.d/99-sungold-ch340.rules
  sudo udevadm control --reload-rules 2>/dev/null || true
  sudo udevadm trigger --subsystem-match=tty 2>/dev/null || true
}

sungold_serial_device_ready() {
  local dev="${SUNGOLD_SERIAL_DEVICE:-/dev/sungold}"
  [[ -e "$dev" ]] || [[ -e /dev/sungold ]]
}

deploy_sungold_stack_if_enabled() {
  [[ "${ENABLE_SUNGOLD:-0}" == "1" ]] || return 0
  if [[ ! -f "$ROOT_DIR/docker-compose.sungold.yml" ]]; then
    echo "[deploy] ENABLE_SUNGOLD=1 but docker-compose.sungold.yml missing — skip." >&2
    return 0
  fi
  install_sungold_udev_rule
  if ! sungold_serial_device_ready; then
    echo "[deploy] ENABLE_SUNGOLD=1 but no USB serial device yet (${SUNGOLD_SERIAL_DEVICE:-/dev/sungold})."
    echo "[deploy] Plug SPH302480A USB-B cable, confirm CH340 (lsusb), set SUNGOLD_SERIAL_DEVICE in .env, re-run deploy."
    return 0
  fi
  echo "[deploy] Building and starting sungold_modbus_ro (read-only Modbus → MQTT) ..."
  if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
    write_dockge_stack_wrapper sungold "$ROOT_DIR/docker-compose.sungold.yml"
    (cd /opt/stacks/sungold && docker compose up -d --build)
  else
    (cd "$ROOT_DIR" && docker compose -f docker-compose.sungold.yml up -d --build)
  fi
}

install_dockge_host_stack() {
  sudo mkdir -p /opt/dockge/data /opt/stacks
  sudo install -m 0644 "$ROOT_DIR/docker-compose.dockge.yml" /opt/dockge/compose.yaml
  echo "[deploy] Starting Dockge (http://<pi-ip>:5006) ..."
  (cd /opt/dockge && sudo docker compose up -d)
}

# docker-compose.homeassistant.yml references env_file: ./ha-discovery.env (gitignored).
ensure_ha_discovery_env_for_compose() {
  local dst="$ROOT_DIR/ha-discovery.env"
  if [[ -f "$dst" ]]; then
    return 0
  fi
  if [[ -f "$ROOT_DIR/swarm/ha-discovery.env" ]]; then
    cp "$ROOT_DIR/swarm/ha-discovery.env" "$dst"
    echo "[deploy] Copied swarm/ha-discovery.env → ./ha-discovery.env"
  elif [[ -f "$ROOT_DIR/swarm/ha-discovery.env.example" ]]; then
    cp "$ROOT_DIR/swarm/ha-discovery.env.example" "$dst"
    echo "[deploy] Created ./ha-discovery.env from swarm/ha-discovery.env.example (set MQTT_PASSWORD etc. if empty)."
  else
    {
      printf '# Minimal stub — compose requires this path.\n'
      printf 'MQTT_HOST=%s\n' "${MQTT_HOST:-127.0.0.1}"
      printf 'MQTT_PORT=%s\n' "${MQTT_PORT:-1883}"
      printf 'MQTT_USER=%s\n' "${MQTT_USER:-}"
      printf 'MQTT_PASSWORD=%s\n' "${MQTT_PASSWORD:-}"
    } >"$dst"
    echo "[deploy] Created ./ha-discovery.env with MQTT_* from current deploy environment."
  fi
  chmod 600 "$dst" 2>/dev/null || true
}

file_has_line() { local f="$1"; shift; local pattern="$*"; grep -Fqx "$pattern" "$f" 2>/dev/null; }

# ------------------------------------------------------------
# 1) Base prerequisites: sudo, curl, Docker, Compose plugin, Mosquitto tools
# ------------------------------------------------------------
if ! need_cmd sudo; then echo "[deploy] sudo is required" >&2; exit 1; fi

if ! need_cmd curl; then apt_install curl ca-certificates gnupg || true; fi

if ! need_cmd docker; then
  echo "[deploy] Installing Docker (docker.io)..."
  apt_install docker.io || true
  ensure_service_active docker
fi

# Docker Compose v2 plugin preferred; fallback to docker-compose
if ! docker compose version >/dev/null 2>&1; then
  if ! need_cmd docker-compose; then
    echo "[deploy] Installing docker compose plugin..."
    apt_install docker-compose-plugin || apt_install docker-compose || true
  fi
fi

ensure_group_member "${SUDO_USER:-$USER}" docker

# Mosquitto broker + clients (for local broker default)
if ! need_cmd mosquitto; then
  echo "[deploy] Installing Mosquitto broker & clients..."
  apt_install mosquitto mosquitto-clients || true
fi
ensure_service_active mosquitto

# Sync Wi‑Fi lines into .env *before* Mosquitto password/listener so .env is complete
# (setup_wifi_env rewrites .env while preserving MQTT_* / ADVKEY_* lines).
if [[ -x "$ROOT_DIR/scripts/setup_wifi_env.sh" ]]; then
  bash "$ROOT_DIR/scripts/setup_wifi_env.sh" || true
fi
if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

# Configure listener if not present; prefer auth if creds provided
# per_listener_settings true avoids Mosquitto 2.x binding a stray default :1883
# when password_file/listener options are split across include snippets.
MOSQ_DIR="/etc/mosquitto"
MOSQ_CONF_DIR="$MOSQ_DIR/conf.d"
sudo mkdir -p "$MOSQ_CONF_DIR"
AUTH_CONF="$MOSQ_CONF_DIR/10-auth.conf"
ALLOW_ALL_CONF="$MOSQ_CONF_DIR/00-allow-all.conf"
if [[ -n "${MQTT_USER:-}" && -n "${MQTT_PASSWORD:-}" ]]; then
  echo "[deploy] Configuring Mosquitto with password auth..."
  sudo rm -f "$ALLOW_ALL_CONF" 2>/dev/null || true
  sudo bash -lc "set -e; mosquitto_passwd -b -c /etc/mosquitto/passwd '$MQTT_USER' '$MQTT_PASSWORD'"
  sudo chown root:mosquitto /etc/mosquitto/passwd
  sudo chmod 640 /etc/mosquitto/passwd
  sudo bash -lc "cat > '$AUTH_CONF' <<CONF
per_listener_settings true
listener ${MQTT_PORT} 0.0.0.0
protocol mqtt
allow_anonymous false
password_file /etc/mosquitto/passwd
log_type error
log_type warning
log_type notice
# keep logs small; systemd/journald caps will also apply
log_dest syslog
CONF"
else
  if [[ ! -f "$ALLOW_ALL_CONF" ]]; then
    echo "[deploy] Configuring Mosquitto (anonymous allowed on ${MQTT_PORT})..."
  sudo bash -lc "cat > '$ALLOW_ALL_CONF' <<CONF
per_listener_settings true
listener ${MQTT_PORT} 0.0.0.0
protocol mqtt
allow_anonymous true
log_type error
log_type warning
log_type notice
log_dest syslog
CONF"
  fi
fi

# mqtt-watchdog.timer uses mosquitto_sub; when allow_anonymous is false it must use credentials.
if [[ -n "${MQTT_USER:-}" && -n "${MQTT_PASSWORD:-}" ]]; then
  sudo tee /etc/mosquitto/watchdog.env >/dev/null <<EOF
MQTT_PORT=${MQTT_PORT}
MQTT_USER=${MQTT_USER@Q}
MQTT_PASSWORD=${MQTT_PASSWORD@Q}
EOF
  sudo chmod 600 /etc/mosquitto/watchdog.env
else
  sudo tee /etc/mosquitto/watchdog.env >/dev/null <<EOF
MQTT_PORT=${MQTT_PORT}
EOF
  sudo chmod 644 /etc/mosquitto/watchdog.env
fi

# Mosquitto 2.x + per_listener_settings: global options (log_dest, log_type, etc.)
# placed BEFORE any "listener" directive trigger a hidden default listener on :1883.
# When conf.d/10-auth.conf then declares "listener 1883 0.0.0.0" the duplicate crashes
# Mosquitto. Fix: strip the main config to persistence + include_dir only.
MOSQ_MAIN="/etc/mosquitto/mosquitto.conf"
if [[ -f "$MOSQ_MAIN" ]]; then
  if grep -qE '^\s*log_dest\b' "$MOSQ_MAIN" 2>/dev/null; then
    echo "[deploy] Cleaning mosquitto.conf: removing log_dest (conflicts with per_listener_settings in conf.d)"
    sudo sed -i '/^\s*log_dest\b/d' "$MOSQ_MAIN"
  fi
  if grep -qE '^\s*log_type\b' "$MOSQ_MAIN" 2>/dev/null; then
    sudo sed -i '/^\s*log_type\b/d' "$MOSQ_MAIN"
  fi
  if ! grep -q 'include_dir /etc/mosquitto/conf.d' "$MOSQ_MAIN" 2>/dev/null; then
    echo "[deploy] Adding include_dir for conf.d to mosquitto.conf"
    echo 'include_dir /etc/mosquitto/conf.d' | sudo tee -a "$MOSQ_MAIN" >/dev/null
  fi
fi

mosquitto_restart_and_verify

# ------------------------------------------------------------
# journald caps to prevent RAM/disk bloat
# ------------------------------------------------------------
JOUR_DIR="/etc/systemd/journald.conf.d"
sudo mkdir -p "$JOUR_DIR"
sudo bash -lc "cat > '$JOUR_DIR/99-victron.conf' <<JCONF
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
MaxRetentionSec=1month
RateLimitIntervalSec=30s
RateLimitBurst=1000
JCONF"
sudo systemctl restart systemd-journald || true

# ------------------------------------------------------------
# Docker daemon default log rotation (applies to all containers)
# ------------------------------------------------------------
DOCKER_DAEMON_JSON=/etc/docker/daemon.json
# Write/repair daemon.json if missing or invalid
ensure_docker_daemon_json() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'DJSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DJSON

  # If file missing, write fresh
  if [[ ! -f "$DOCKER_DAEMON_JSON" ]]; then
    echo "[deploy] Writing Docker daemon log defaults (10m x3) ..."
    sudo install -o root -g root -m 0644 "$tmp" "$DOCKER_DAEMON_JSON"
    return 0
  fi

  # If existing content clearly invalid (unquoted keys) or missing required keys, back up and replace
  if ! grep -q '"log-driver"' "$DOCKER_DAEMON_JSON" ||
     ! grep -q '"log-opts"' "$DOCKER_DAEMON_JSON" ||
     grep -qE '(^|[\{,[:space:]])log-driver\s*:' "$DOCKER_DAEMON_JSON"; then
    echo "[deploy] Repairing invalid $DOCKER_DAEMON_JSON (backing up and replacing) ..."
    sudo cp -a "$DOCKER_DAEMON_JSON" "$DOCKER_DAEMON_JSON.bak.$(date +%s)" || true
    sudo install -o root -g root -m 0644 "$tmp" "$DOCKER_DAEMON_JSON"
  fi
}

merge_docker_registry_mirror_into_daemon_json() {
  [[ "${ENABLE_DOCKER_REGISTRY_MIRROR:-1}" != "1" ]] && return 0
  if ! need_cmd python3; then
    echo "[deploy] python3 missing; skipping registry-mirrors merge." >&2
    return 0
  fi
  local mirror="${DOCKER_REGISTRY_MIRROR:-http://192.168.0.111:5000}"
  echo "[deploy] Merging Docker registry mirror into $DOCKER_DAEMON_JSON ($mirror) ..."
  if ! sudo env DOCKER_DAEMON_JSON="$DOCKER_DAEMON_JSON" MIRROR="$mirror" python3 <<'PY'
import json
import os

path = os.environ["DOCKER_DAEMON_JSON"]
mirror = os.environ["MIRROR"]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
existing = list(data.get("registry-mirrors") or [])
if mirror not in existing:
    existing.append(mirror)
data["registry-mirrors"] = existing
tmp = path + ".tmp.merge"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
  then
    echo "[deploy] WARN: could not merge registry-mirrors into $DOCKER_DAEMON_JSON" >&2
  fi
}

ensure_docker_daemon_json
merge_docker_registry_mirror_into_daemon_json
ensure_service_active docker
# Try restart; if it fails due to config, quarantine the file and start with defaults
if ! sudo systemctl restart docker; then
  echo "[deploy] Docker failed to restart; quarantining $DOCKER_DAEMON_JSON and retrying ..." >&2
  sudo mv -f "$DOCKER_DAEMON_JSON" "$DOCKER_DAEMON_JSON.broken.$(date +%s)" || true
  sudo systemctl restart docker || true
fi

# ------------------------------------------------------------
# Logrotate for app and HA logs
# ------------------------------------------------------------
if ! need_cmd logrotate; then apt_install logrotate || true; fi
sudo bash -lc "cat > /etc/logrotate.d/victron_ble2mqtt <<LROT
/var/log/victron_ble2mqtt.log {
  size 5M
  rotate 7
  compress
  copytruncate
  missingok
}
LROT"
sudo bash -lc "cat > /etc/logrotate.d/homeassistant <<LROT
/opt/homeassistant/home-assistant.log {
  size 10M
  rotate 7
  compress
  copytruncate
  missingok
}
LROT"
# Ensure logrotate timer is active
ensure_service_active logrotate.timer || true

# ------------------------------------------------------------
# 2) Host BLE stack readiness (BlueZ, dbus, rfkill, bluetoothd)
# ------------------------------------------------------------
if ! need_cmd bluetoothctl; then
  echo "[deploy] Installing BlueZ..."
  apt_install bluez rfkill dbus || true
fi
ensure_service_active bluetooth || true
sudo rfkill unblock bluetooth || true

# ------------------------------------------------------------
# 3) Optional performance/network tuning
# ------------------------------------------------------------
if [[ "${ENABLE_PERF_TUNING:-0}" == "1" ]]; then
  echo "[deploy] Applying performance tuning (systemd + udev) ..."
  bash "$ROOT_DIR/scripts/apply_max_performance.sh" || true
fi

# ------------------------------------------------------------
# 4) Build image and prepare runtime files
# ------------------------------------------------------------
if [[ ! -f requirements.txt ]]; then echo "[deploy] requirements.txt missing" >&2; exit 1; fi
if [[ ! -f victron-secrets.env ]]; then
  echo "[deploy] Creating placeholder victron-secrets.env (edit ADVKEY_* values; or set ADVKEY_* in .env — .env overrides this file)"
  cat > victron-secrets.env <<'ENV'
# ADVKEY placeholders (32-hex). Update with your device keys.
ADVKEY_BATTERY_1=
ADVKEY_BATTERY_2=
ADVKEY_SOLAR_CONTROLLER=
ENV
fi

# Log file for container bind mount
sudo touch /var/log/victron_ble2mqtt.log
sudo chown "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" /var/log/victron_ble2mqtt.log || true

maybe_mount_truenas_hub_for_victron

ensure_victron_hub_wheel_dir_on_cluster

prepare_victron_docker_build_env

load_all_hub_images

echo "[deploy] Building Docker image (victron_ble2mqtt:local, PIP_OFFLINE=${PIP_OFFLINE:-0}) ..."
DOCKER_BUILDKIT=1 docker build --build-arg "PIP_OFFLINE=${PIP_OFFLINE:-0}" -t victron_ble2mqtt:local .

# ------------------------------------------------------------
# 5) Dockge + stack wrappers; legacy systemd runners removed
# ------------------------------------------------------------
cleanup_legacy_systemd_runners

if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
  echo "[deploy] Installing Dockge under /opt/dockge and wrappers under /opt/stacks ..."
  install_dockge_host_stack
  write_dockge_stack_wrapper victron "$ROOT_DIR/docker-compose.victron.yml"
  write_dockge_stack_wrapper homeassistant "$ROOT_DIR/docker-compose.homeassistant.yml"
  if [[ "${ENABLE_AUTOHEAL:-1}" == "1" ]]; then
    write_dockge_stack_wrapper autoheal "$ROOT_DIR/docker-compose.autoheal.yml"
  fi
  if [[ "${ENABLE_TOOLS}" == "1" ]]; then
    write_dockge_stack_wrapper tools "$ROOT_DIR/docker-compose.tools.yml"
  fi
else
  echo "[deploy] ENABLE_DOCKGE=0 — skipping Dockge install (Compose files run from repo paths only)."
fi

echo "[deploy] Starting victron_ble2mqtt stack ..."
if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
  (cd /opt/stacks/victron && docker compose up -d --build)
else
  (cd "$ROOT_DIR" && docker compose -f docker-compose.victron.yml up -d --build)
fi

if [[ "${ENABLE_AUTOHEAL:-1}" == "1" ]]; then
  echo "[deploy] Starting autoheal (restarts unhealthy containers labeled autoheal=true) ..."
  if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
    (cd /opt/stacks/autoheal && docker compose up -d)
  else
    (cd "$ROOT_DIR" && docker compose -f docker-compose.autoheal.yml up -d)
  fi
fi

if [[ "${ENABLE_TOOLS}" == "1" ]]; then
  echo "[deploy] Starting Watchtower (tools) stack ..."
  if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
    (cd /opt/stacks/tools && docker compose up -d)
  else
    (cd "$ROOT_DIR" && docker compose -f docker-compose.tools.yml up -d)
  fi
fi

deploy_sungold_stack_if_enabled

# Optional: Wi‑Fi failover monitor
if [[ "${ENABLE_FAILOVER_MONITOR:-0}" == "1" ]]; then
  if [[ -f "$ROOT_DIR/systemd/wifi-failover-monitor@.service" ]]; then
    echo "[deploy] Enabling wifi-failover-monitor@${SUDO_USER:-$USER}.service ..."
    sudo install -m 0644 -D "$ROOT_DIR/systemd/wifi-failover-monitor@.service" /etc/systemd/system/wifi-failover-monitor@.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now "wifi-failover-monitor@${SUDO_USER:-$USER}.service" || true
  fi
fi

# Legacy systemd HA watchdog (duplicates Compose HTTP healthcheck). Prefer ENABLE_AUTOHEAL + Compose labels.
if [[ "${ENABLE_HA_WATCHDOG}" == "1" ]]; then
  if [[ -f "$ROOT_DIR/scripts/ha-watchdog.sh" && -f "$ROOT_DIR/systemd/ha-watchdog.service" && -f "$ROOT_DIR/systemd/ha-watchdog.timer" ]]; then
    echo "[deploy] Installing HA watchdog service + timer (legacy; ENABLE_HA_WATCHDOG=1) ..."
    sudo install -m 0755 -D "$ROOT_DIR/scripts/ha-watchdog.sh" /usr/local/bin/ha-watchdog.sh
    sudo install -m 0644 -D "$ROOT_DIR/systemd/ha-watchdog.service" /etc/systemd/system/ha-watchdog.service
    sudo install -m 0644 -D "$ROOT_DIR/systemd/ha-watchdog.timer" /etc/systemd/system/ha-watchdog.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now ha-watchdog.timer || true
  fi
else
  if systemctl is-enabled --quiet ha-watchdog.timer 2>/dev/null; then
    echo "[deploy] ENABLE_HA_WATCHDOG=0 — disabling legacy ha-watchdog.timer (Compose healthcheck + autoheal)."
    sudo systemctl disable --now ha-watchdog.timer || true
  fi
fi

# VS Code server cleanup timer (optional, default on)
if [[ "${ENABLE_VSCODE_CLEANUP}" == "1" ]]; then
  if [[ -f "$ROOT_DIR/systemd/vscode-server-cleanup.service" && -f "$ROOT_DIR/systemd/vscode-server-cleanup.timer" && -f "$ROOT_DIR/scripts/vscode_server_cleanup.sh" ]]; then
    echo "[deploy] Installing VS Code cleanup timer ..."
    sudo install -m 0755 -D "$ROOT_DIR/scripts/vscode_server_cleanup.sh" /usr/local/bin/vscode-server-cleanup.sh
    render_unit_with_user_path "$ROOT_DIR/systemd/vscode-server-cleanup.service" /etc/systemd/system/vscode-server-cleanup.service
    sudo install -m 0644 -D "$ROOT_DIR/systemd/vscode-server-cleanup.timer" /etc/systemd/system/vscode-server-cleanup.timer
    sudo systemctl daemon-reload
    sudo systemctl enable --now vscode-server-cleanup.timer || true
  fi
fi

# Unattended upgrades (security only, no auto-reboot) – optional
if [[ "${ENABLE_UNATTENDED_UPGRADES}" == "1" ]]; then
  echo "[deploy] Enabling unattended-upgrades (security only) ..."
  apt_install unattended-upgrades || true
  # Security origins only, do not reboot automatically
  sudo bash -lc "cat > /etc/apt/apt.conf.d/51-victron-unattended <<CFG
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=",
    "origin=Debian,codename=,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
CFG"
  ensure_service_active unattended-upgrades || true
  ensure_service_active apt-daily.timer || true
  ensure_service_active apt-daily-upgrade.timer || true
fi

# Docker prune (weekly) – optional, conservative retention
if [[ "${ENABLE_DOCKER_PRUNE}" == "1" ]]; then
  echo "[deploy] Installing docker prune weekly timer (tracked systemd units) ..."
  sudo install -m 0644 -D "$ROOT_DIR/systemd/docker-prune.service" /etc/systemd/system/docker-prune.service
  sudo install -m 0644 -D "$ROOT_DIR/systemd/docker-prune.timer" /etc/systemd/system/docker-prune.timer
  sudo systemctl daemon-reload
  sudo systemctl enable --now docker-prune.timer || true
fi

# MQTT broker watchdog (minute) – optional
if [[ "${ENABLE_MQTT_WATCHDOG}" == "1" ]]; then
  echo "[deploy] Installing MQTT watchdog (tracked script + systemd units) ..."
  sudo install -m 0755 -D "$ROOT_DIR/scripts/mqtt-watchdog.sh" /usr/local/bin/mqtt-watchdog.sh
  sudo install -m 0644 -D "$ROOT_DIR/systemd/mqtt-watchdog.service" /etc/systemd/system/mqtt-watchdog.service
  sudo install -m 0644 -D "$ROOT_DIR/systemd/mqtt-watchdog.timer" /etc/systemd/system/mqtt-watchdog.timer
  sudo systemctl daemon-reload
  sudo systemctl enable --now mqtt-watchdog.timer || true
fi
# ------------------------------------------------------------
# 6) Home Assistant container (host network)
# ------------------------------------------------------------
if [[ "${ENABLE_HOME_ASSISTANT:-1}" != "1" ]]; then
  echo "[deploy] ENABLE_HOME_ASSISTANT=0 — skipping Home Assistant config and Compose (no GHCR pull)."
else
HA_TZ="${TZ:-America/Chicago}"
HA_CONFIG_DIR="/opt/homeassistant"
sudo mkdir -p "$HA_CONFIG_DIR"
sudo chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$HA_CONFIG_DIR" || true
if [[ ! -f "$HA_CONFIG_DIR/configuration.yaml" ]]; then
  cat > "$HA_CONFIG_DIR/configuration.yaml" <<YAML
homeassistant:
  time_zone: ${HA_TZ}
YAML
fi

if [[ "${FORCE_HA_MQTT_YAML}" == "1" ]]; then
  echo "[deploy] FORCE_HA_MQTT_YAML=1 is ignored: HA 2026+ rejects YAML broker settings. MQTT is enabled via config entry after HA starts."
fi

# Bluetooth on HA Container: D-Bus + caps (see HA repairs / habluetooth.manager).
# https://www.home-assistant.io/integrations/bluetooth/#requirements-for-linux-systems
ha_homeassistant_bluetooth_ok() {
  docker inspect homeassistant -f '{{range $m := .Mounts}}{{println $m.Destination}}{{end}}' 2>/dev/null | grep -q '^/run/dbus$' || return 1
  local caps
  caps="$(docker inspect homeassistant -f '{{range .HostConfig.CapAdd}}{{.}} {{end}}' 2>/dev/null || true)"
  [[ "$caps" == *NET_ADMIN* ]] || return 1
  [[ "$caps" == *NET_RAW* ]] || return 1
  return 0
}

if docker ps -a --format '{{.Names}}' | grep -qw homeassistant; then
  if ! ha_homeassistant_bluetooth_ok; then
    echo "[deploy] Recreating homeassistant container (Bluetooth: /run/dbus + NET_ADMIN/NET_RAW per HA docs)..."
    docker rm -f homeassistant >/dev/null 2>&1 || true
  fi
fi

export TZ="${HA_TZ}"
ensure_ha_discovery_env_for_compose
ensure_ha_image
echo "[deploy] Starting Home Assistant via Compose (image=${HA_IMAGE}) ..."
if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
  (cd /opt/stacks/homeassistant && docker compose up -d)
else
  (cd "$ROOT_DIR" && docker compose -f docker-compose.homeassistant.yml up -d)
fi

echo "[deploy] Waiting for Home Assistant on http://localhost:8123 ..."
for i in {1..30}; do
  if curl -fsS http://localhost:8123 >/dev/null 2>&1; then
    echo "[deploy] Home Assistant is up."
    break
  fi
  sleep 2
done

if [[ "${ENABLE_HA_MQTT_INTEGRATION}" == "1" ]]; then
  echo "[deploy] Ensuring Home Assistant MQTT config entry (HA 2026+; not YAML) ..."
  bash "$ROOT_DIR/scripts/ha_enable_mqtt_integration.sh" || echo "[deploy] MQTT integration script failed (check HA logs)."
fi

fi
# ------------------------------------------------------------
# 7) Quick sanity: show container status and recent logs snippet
# ------------------------------------------------------------
echo "[deploy] Container status:"
docker ps --format '{{.Names}}\t{{.Status}}' | egrep 'victron|homeassistant|sungold|dockge|watchtower|autoheal' || true

if [[ "${ENABLE_DOCKGE}" == "1" ]]; then
  echo "[deploy] Dockge UI: http://${MQTT_HOST}:5006 (stack files live under /opt/stacks; included Compose paths resolve to ${ROOT_DIR})."
fi

echo "[deploy] victron_ble2mqtt env (sanitized — passwords and ADVKEY hex hidden):"
# Config.Env may list the same key twice (--env-file placeholders + -e from redeploy).
# Last assignment wins at runtime; dedupe so this summary matches what the process sees.
if docker ps -a --format '{{.Names}}' | grep -qw victron_ble2mqtt; then
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' victron_ble2mqtt 2>/dev/null \
    | egrep '^(MQTT_|ADVKEY_|BLE_ADAPTER|VICTRON_BLE_ADAPTER)' | tac | awk -F= '!seen[$1]++' | tac \
  | while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    k="${line%%=*}"
    v="${line#*=}"
    case "$k" in
      MQTT_PASSWORD)
        if [[ -n "$v" ]]; then echo "MQTT_PASSWORD=(set, hidden)"; else echo "MQTT_PASSWORD=(empty)"; fi
        ;;
      ADVKEY_*)
        vl=${#v}
        if [[ "$vl" -eq 0 ]]; then echo "${k}=(empty)"
        elif [[ "$vl" -eq 32 ]]; then echo "${k}=(32 hex chars, hidden)"
        else echo "${k}=(length ${vl}, hidden)"; fi
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done || true
else
  echo "(victron_ble2mqtt container not present)"
fi

echo "[deploy] Tail victron_ble2mqtt logs: docker logs -f victron_ble2mqtt"
echo "[deploy] Done."
