#!/usr/bin/env bash
# Pi 5 house-edge stack: AdGuard DNS, Theengs BLE→MQTT (Pi 4 broker), node_exporter.
# Invoked by scripts/deploy.sh when HOST_ROLE=pi5. Safe to re-run.
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
PI5="$ROOT_DIR/hosts/pi5"
LEGACY_MONITORING="${PI5_LEGACY_MONITORING:-/home/n4s1/monitoring/hosts/pi5-dns}"
PI4_MQTT_LAN="${PI4_MQTT_LAN:-192.168.0.223}"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

apt_install() {
  local pkgs=("$@")
  if ! need_cmd apt-get; then
    echo "[deploy-pi5] apt-get not available; install ${pkgs[*]} manually." >&2
    return 1
  fi
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[deploy-pi5] run as root: sudo bash scripts/deploy.sh  (HOST_ROLE=pi5)" >&2
  exit 1
fi

if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

echo "[deploy-pi5] HOST_ROLE=pi5 — AdGuard + Theengs + node_exporter (no HA / Victron / Mosquitto here)"

if ! need_cmd curl; then apt_install curl ca-certificates gnupg || true; fi
if ! need_cmd docker; then
  echo "[deploy-pi5] Installing Docker..."
  apt_install docker.io || true
  sudo systemctl enable --now docker || true
fi
if ! docker compose version >/dev/null 2>&1; then
  apt_install docker-compose-plugin || apt_install docker-compose || true
fi
if ! need_cmd bluetoothctl; then
  apt_install bluez rfkill dbus || true
fi
sudo systemctl enable --now bluetooth 2>/dev/null || true
sudo rfkill unblock bluetooth || true

mkdir -p /opt/adguard/conf /opt/adguard/work "$PI5"

# Adopt secrets from the earlier monitoring-repo layout, if present.
if [[ -d "$LEGACY_MONITORING" ]]; then
  if [[ ! -s "$PI5/adguard-exporter.password" && -s "$LEGACY_MONITORING/adguard-exporter.password" ]]; then
    echo "[deploy-pi5] Copying AdGuard exporter password from $LEGACY_MONITORING"
    cp -a "$LEGACY_MONITORING/adguard-exporter.password" "$PI5/adguard-exporter.password"
  fi
  if [[ ! -f "$PI5/mqtt.env" && -f "$LEGACY_MONITORING/mqtt.env" ]]; then
    echo "[deploy-pi5] Copying Theengs mqtt.env from $LEGACY_MONITORING"
    cp -a "$LEGACY_MONITORING/mqtt.env" "$PI5/mqtt.env"
  fi
fi

if [[ ! -f "$PI5/mqtt.env" ]]; then
  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    echo "[deploy-pi5] missing .env and hosts/pi5/mqtt.env — copy dotenv.sample and set MQTT_* to the Pi 4 broker." >&2
    exit 1
  fi
  python3 "$ROOT_DIR/scripts/write_theengs_mqtt_env.py" "$ROOT_DIR/.env" "$PI5/mqtt.env" "$PI4_MQTT_LAN"
fi
chmod 600 "$PI5/mqtt.env" 2>/dev/null || true

mqtt_host="$(awk -F= '/^MQTT_HOST=/{print $2; exit}' "$PI5/mqtt.env" | tr -d '\r')"
local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
if [[ -z "$mqtt_host" || "$mqtt_host" == "localhost" || "$mqtt_host" == "127.0.0.1" ]]; then
  echo "[deploy-pi5] mqtt.env MQTT_HOST must be the Pi 4 LAN IP ($PI4_MQTT_LAN), not loopback." >&2
  exit 1
fi
if [[ -n "$local_ip" && "$mqtt_host" == "$local_ip" ]]; then
  echo "[deploy-pi5] mqtt.env MQTT_HOST=$mqtt_host is this Pi — Theengs must publish to the Pi 4 broker." >&2
  exit 1
fi

if [[ -s "$PI5/adguard-exporter.password" ]]; then
  if [[ "$(tail -c1 "$PI5/adguard-exporter.password" | wc -l)" -ne 0 ]]; then
    printf '%s' "$(cat "$PI5/adguard-exporter.password")" > "$PI5/adguard-exporter.password.tmp"
    mv "$PI5/adguard-exporter.password.tmp" "$PI5/adguard-exporter.password"
  fi
  chmod 600 "$PI5/adguard-exporter.password"
fi

echo "[deploy-pi5] starting node_exporter"
docker compose -f "$PI5/docker-compose.node-exporter.yml" up -d

echo "[deploy-pi5] starting AdGuard Home"
docker compose -f "$PI5/docker-compose.adguard.yml" up -d adguardhome
if [[ -s "$PI5/adguard-exporter.password" ]]; then
  echo "[deploy-pi5] starting adguard-exporter"
  docker compose --profile exporter -f "$PI5/docker-compose.adguard.yml" up -d
else
  lan="${local_ip:-<pi5-ip>}"
  echo "[deploy-pi5] no hosts/pi5/adguard-exporter.password — exporter skipped."
  echo "[deploy-pi5] If the wizard is still open: http://${lan}:3000  (admin port 8080, DNS 53, user n4s1)"
  echo "[deploy-pi5] Then: printf '%s' 'PASSWORD' | sudo tee $PI5/adguard-exporter.password >/dev/null"
  echo "[deploy-pi5]         sudo chmod 600 $PI5/adguard-exporter.password && sudo bash scripts/deploy.sh"
fi

echo "[deploy-pi5] starting Theengs BLE gateway → $mqtt_host:1883"
docker compose -f "$PI5/docker-compose.theengs.yml" up -d
sleep 2
logpath="$(docker inspect --format='{{.LogPath}}' pi5-theengs-gateway 2>/dev/null || true)"
if [[ -n "$logpath" && -f "$logpath" ]]; then
  : > "$logpath" || true
fi

echo ""
echo "[deploy-pi5] containers:"
docker ps --filter name=pi5- --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo ""
echo "[deploy-pi5] AdGuard UI :8080   DNS :53   node_exporter :9100   adguard-exporter :9617"
echo "[deploy-pi5] Theengs topic home/TheengsGateway-pi5/BTtoMQTT  (decoded BLE only)"
echo "[deploy-pi5] Wi-Fi HVAC (Ecobee/Rheem) is not forwarded here — add HomeKit Device / EcoNet on Pi 4 HA."
echo "[deploy-pi5] Done."
