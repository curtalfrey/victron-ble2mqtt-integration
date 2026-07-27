#!/usr/bin/env bash
# Reset Mosquitto, Home Assistant, and Victron containers/software, preserving secrets.
# - Backs up: .env, victron-secrets.env, HA config (/opt/homeassistant), Mosquitto config/state
# - Removes: containers/images, Mosquitto packages/configs
# - Redeploys: scripts/deploy_local.sh
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TS=$(date +%Y%m%d-%H%M%S)
BK="${ROOT_DIR}/backups/${TS}"
mkdir -p "$BK"
echo "[reset] Backups -> $BK"

# 1) Back up env files
[[ -f ./.env ]] && cp -av ./.env "$BK/" || true
[[ -f ./victron-secrets.env ]] && cp -av ./victron-secrets.env "$BK/" || true

# 2) Back up HA config (if present)
if [[ -d /opt/homeassistant ]]; then
  echo "[reset] Backing up /opt/homeassistant ..."
  sudo tar -C / -czf "$BK/homeassistant-config.tgz" opt/homeassistant || true
fi

# 3) Back up Mosquitto config/state (if present)
if [[ -d /etc/mosquitto || -d /var/lib/mosquitto ]]; then
  echo "[reset] Backing up mosquitto config/state ..."
  sudo tar -C / -czf "$BK/mosquitto-backup.tgz" etc/mosquitto var/lib/mosquitto 2>/dev/null || true
fi

# 4) Stop and remove containers
echo "[reset] Removing containers ..."
for c in victron_ble2mqtt homeassistant mosquitto; do docker rm -f "$c" >/dev/null 2>&1 || true; done

# 5) Remove common images (best-effort)
echo "[reset] Removing images ..."
docker rmi -f victron_ble2mqtt:local \
  ghcr.io/home-assistant/home-assistant:2026.7.3 \
  ghcr.io/home-assistant/home-assistant:stable >/dev/null 2>&1 || true

# 6) Remove Mosquitto packages/configs (system install)
echo "[reset] Purging Mosquitto packages ..."
sudo systemctl stop mosquitto >/dev/null 2>&1 || true
sudo apt-get -y update >/dev/null 2>&1 || true
sudo apt-get -y purge mosquitto mosquitto-clients >/dev/null 2>&1 || true
sudo rm -rf /etc/mosquitto /var/lib/mosquitto >/dev/null 2>&1 || true
sudo apt-get -y autoremove >/dev/null 2>&1 || true

# 7) Redeploy fresh
echo "[reset] Running deploy_local.sh ..."
bash "${ROOT_DIR}/scripts/deploy_local.sh"

echo "[reset] Done. Backups at: $BK"