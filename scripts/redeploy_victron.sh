#!/usr/bin/env bash
# Recreate victron_ble2mqtt container with env from .env and victron-secrets.env
# - MQTT_HOST from .env, else first address from hostname -I, else 127.0.0.1
# - Host networking, NET_ADMIN, same mounts as compose
set -euo pipefail

cd "$(dirname "$0")/.."

# Load victron-secrets.env first, then .env so .env wins on duplicate keys.
# (deploy.sh ships victron-secrets.env with empty ADVKEY_* placeholders; if those
# were sourced after .env they would wipe ADVKEY_* that only exist in .env.)
if [[ -f ./victron-secrets.env ]]; then set -a; . ./victron-secrets.env; set +a; fi
if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

# After sourcing victron-secrets.env + .env, MQTT_HOST may still be localhost from
# an older secrets file. Treat loopback as unset and prefer the Pi's LAN address.
MQTT_HOST_EFFECTIVE="${MQTT_HOST:-}"
if [[ -z "$MQTT_HOST_EFFECTIVE" || "$MQTT_HOST_EFFECTIVE" == "localhost" || "$MQTT_HOST_EFFECTIVE" == "127.0.0.1" ]]; then
  MQTT_HOST_EFFECTIVE="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
fi
if [[ -z "$MQTT_HOST_EFFECTIVE" ]]; then
  MQTT_HOST_EFFECTIVE="127.0.0.1"
fi
echo "[redeploy] MQTT_HOST=${MQTT_HOST_EFFECTIVE}" >&2

MQTT_PORT_EFFECTIVE="${MQTT_PORT:-1883}"
if ! timeout 4 bash -c "exec 3<>/dev/tcp/${MQTT_HOST_EFFECTIVE}/${MQTT_PORT_EFFECTIVE}" 2>/dev/null; then
  echo "[redeploy] ERROR: nothing accepting TCP on ${MQTT_HOST_EFFECTIVE}:${MQTT_PORT_EFFECTIVE} (broker down or wrong host)." >&2
  echo "[redeploy] Install/start Mosquitto, then: sudo bash scripts/deploy.sh" >&2
  exit 1
fi

# ADVKEY_* must be exactly 32 hex (VictronConnect Instant Readout).
# Do not silently truncate a longer paste -- that decrypts as garbage.
sanitize_advkey() {
  local v="$1"
  v="${v//[^0-9A-Fa-f]/}"
  if [[ ${#v} -ne 32 ]]; then
    echo "[redeploy] ERROR: advertisement key must be exactly 32 hex characters (got ${#v}). Copy Instant Readout Details from VictronConnect; do not trim a longer paste." >&2
    exit 1
  fi
  echo "$v"
}
ADVKEY_BATTERY_1_SAN="$(sanitize_advkey "${ADVKEY_BATTERY_1:-}")"
ADVKEY_BATTERY_2_SAN="$(sanitize_advkey "${ADVKEY_BATTERY_2:-}")"
ADVKEY_SOLAR_CONTROLLER_SAN="$(sanitize_advkey "${ADVKEY_SOLAR_CONTROLLER:-}")"

# Ensure image
IMG="victron_ble2mqtt:local"
mkdir -p ./wheels
export PIP_OFFLINE="${PIP_OFFLINE:-0}"
if [[ -d /mnt/cluster/wheels/victron ]]; then
  bash ./scripts/sync-victron-wheels-from-hub.sh || true
fi
whl_count="$(find ./wheels -maxdepth 1 -type f -name '*.whl' 2>/dev/null | wc -l)"
whl_count="${whl_count// /}"
if [[ "${whl_count:-0}" -gt 0 ]]; then
  export PIP_OFFLINE=1
else
  export PIP_OFFLINE=0
fi

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  DOCKER_BUILDKIT=1 docker build --build-arg "PIP_OFFLINE=${PIP_OFFLINE}" -t "$IMG" .
fi

# Stop old container
docker rm -f victron_ble2mqtt >/dev/null 2>&1 || true

# Run fresh container
docker run -d --name victron_ble2mqtt --restart unless-stopped \
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=5 \
  --network host --cap-add NET_ADMIN --privileged \
  --env-file ./victron-secrets.env \
  -e MQTT_HOST="${MQTT_HOST_EFFECTIVE}" -e MQTT_PORT="${MQTT_PORT_EFFECTIVE}" \
  -e MQTT_USER="${MQTT_USER:-}" -e MQTT_PASSWORD="${MQTT_PASSWORD:-}" \
  -e MAIN_UID="${MAIN_UID:-}" -e PUBLISH_CONFIG_THROTTLE_SEC="${PUBLISH_CONFIG_THROTTLE_SEC:-60}" \
  -e SYSTEM_POLL_THROTTLE_SEC="${SYSTEM_POLL_THROTTLE_SEC:-3}" \
  -e LOG_LEVEL="${LOG_LEVEL:-INFO}" \
  -e BLE_ADAPTER="${BLE_ADAPTER:-${VICTRON_BLE_ADAPTER:-}}" \
  -e ADVKEY_BATTERY_1="${ADVKEY_BATTERY_1_SAN}" \
  -e ADVKEY_BATTERY_2="${ADVKEY_BATTERY_2_SAN}" \
  -e ADVKEY_SOLAR_CONTROLLER="${ADVKEY_SOLAR_CONTROLLER_SAN}" \
  -e PYTHONPATH=/work/override:/work \
  -v "$(pwd)/override":/work/override:ro \
  -v "$(pwd)/override/victron_ble2mqtt":/app/override/victron_ble2mqtt:ro \
  -v "$(pwd)/victron_ble2mqtt":/app/victron_ble2mqtt:ro \
  -v "$(pwd)/swarm":/work/swarm:ro \
  -v /var/log/victron_ble2mqtt.log:/logs/victron_ble2mqtt.log:rw \
  -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro \
  -v /var/run/dbus:/var/run/dbus:ro \
  -v /var/lib/bluetooth:/var/lib/bluetooth:ro \
  "$IMG"

sleep 3
echo "[redeploy] MQTT connection env (password hidden):"
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' victron_ble2mqtt 2>/dev/null | grep -E '^MQTT_HOST=|^MQTT_PORT=|^MQTT_USER=' || true
if docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' victron_ble2mqtt 2>/dev/null | grep -q '^MQTT_PASSWORD=.\{1,\}'; then
  echo "MQTT_PASSWORD=(set, hidden)"
else
  echo "MQTT_PASSWORD=(empty or unset)"
fi
