#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ------------------------------------------------------------
# Load .env and set defaults
# ------------------------------------------------------------
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# Keep MQTT local so IP changes (eth0<->wlan0) don’t break anything
: "${MQTT_HOST:=127.0.0.1}"
: "${MQTT_PORT:=1883}"
# Modern HA prefers UI-based MQTT integration. Default to UI; YAML remains opt-in.
: "${FORCE_HA_MQTT_YAML:=0}"

# ------------------------------------------------------------
# Wi‑Fi bring-up (NetworkManager preferred, fallback to wpa_supplicant)
# ------------------------------------------------------------
ensure_wifi() {
  if ! ip link show wlan0 >/dev/null 2>&1; then
    echo "wlan0 interface not found; skipping Wi‑Fi setup."
    return 0
  fi

  if command -v nmcli >/dev/null 2>&1; then
    echo "Configuring Wi‑Fi with NetworkManager..."
    sudo systemctl enable --now NetworkManager || true
    sudo nmcli radio wifi on || true
    # Ensure NM manages wlan0
    sudo nmcli dev set wlan0 managed yes || true

    # Import SSID/PSK from wpa_supplicant if not provided
    if [[ -z "${WIFI_SSID-}" || -z "${WIFI_PASSWORD-}" ]]; then
      for C in /etc/wpa_supplicant/wpa_supplicant-wlan0.conf /etc/wpa_supplicant/wpa_supplicant.conf; do
        if [[ -z "${WIFI_SSID-}" && -r "$C" ]]; then
          SSID=$(awk -F= '/^[[:space:]]*ssid=/ {gsub(/"/,"",$2); print $2; exit}' "$C" || true)
        fi
        if [[ -z "${WIFI_PASSWORD-}" && -r "$C" ]]; then
          PSK=$(awk -F= '/^[[:space:]]*psk=/ {gsub(/"/,"",$2); print $2; exit}' "$C" || true)
        fi
      done
      [[ -n "${SSID-}" ]] && WIFI_SSID="$SSID"
      [[ -n "${PSK-}" ]] && WIFI_PASSWORD="$PSK"
      [[ -n "${WIFI_SSID-}" ]] && echo "Detected SSID: $WIFI_SSID"
    fi

    if [[ -n "${WIFI_SSID-}" ]]; then
      if ! nmcli -t -f NAME connection show | grep -Fxq "$WIFI_SSID"; then
        sudo nmcli con add type wifi ifname wlan0 con-name "$WIFI_SSID" ssid "$WIFI_SSID" || true
      fi
      if [[ -n "${WIFI_PASSWORD-}" ]]; then
        sudo nmcli con modify "$WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PASSWORD" || true
      fi
      sudo nmcli con modify "$WIFI_SSID" connection.autoconnect yes || true
      sudo nmcli dev disconnect wlan0 || true
      sudo nmcli con up "$WIFI_SSID" ifname wlan0 || true
    else
      # Try to bring up an existing Wi‑Fi connection profile on wlan0
      EXISTING_WIFI=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | awk -F: '/:802-11-wireless:/ {print $1; exit}')
      [[ -z "$EXISTING_WIFI" ]] && EXISTING_WIFI=$(nmcli -t -f NAME,TYPE connection show | awk -F: '/:802-11-wireless$/ {print $1; exit}')
      if [[ -n "$EXISTING_WIFI" ]]; then
        echo "Bringing up existing Wi‑Fi connection: $EXISTING_WIFI"
        sudo nmcli con modify "$EXISTING_WIFI" connection.autoconnect yes || true
        sudo nmcli dev disconnect wlan0 || true
        sudo nmcli con up "$EXISTING_WIFI" ifname wlan0 || true
      else
        echo "No Wi‑Fi SSID provided and no existing Wi‑Fi profile found. Set WIFI_SSID and WIFI_PASSWORD in .env."
      fi
    fi

    nmcli -t -f DEVICE,STATE,CONNECTION device | grep '^wlan0' || true
    return 0
  fi

  echo "NetworkManager not found, using wpa_supplicant..."
  if ! command -v wpa_supplicant >/dev/null 2>&1; then
    if [ -x "$(command -v apt-get)" ]; then
      sudo apt-get update
      sudo apt-get install -y wpasupplicant wireless-tools dhcpcd5 || true
    fi
  fi
  if [[ -n "${WIFI_SSID-}" ]]; then
    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
    if [[ ! -f "$WPA_CONF" ]]; then
      echo "Creating $WPA_CONF for SSID $WIFI_SSID..."
      sudo bash -c "cat > '$WPA_CONF' <<WPA
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid=\"$WIFI_SSID\"
    psk=\"$WIFI_PASSWORD\"
    key_mgmt=WPA-PSK
}
WPA"
      sudo chmod 600 "$WPA_CONF"
      sudo chown root:root "$WPA_CONF"
    fi
    sudo systemctl enable --now wpa_supplicant@wlan0.service || true
    if systemctl list-unit-files | grep -q '^dhcpcd.service'; then
      sudo systemctl enable --now dhcpcd || true
    else
      sudo dhclient -nw wlan0 || true
    fi
  fi
  iw dev wlan0 link || true
}

ensure_wifi

# ------------------------------------------------------------
# Ethernet→Wi‑Fi failover: prefer eth0 when present
# ------------------------------------------------------------
ensure_failover_routing() {
  ETH=eth0; WLAN=wlan0
  if command -v nmcli >/dev/null 2>&1; then
    echo "Setting route metrics with NetworkManager..."
    sudo systemctl enable --now NetworkManager || true
    eth_con=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$ETH" '$2==d{print $1; exit}')
    [[ -z "$eth_con" ]] && eth_con="$ETH" && nmcli con add type ethernet ifname "$ETH" con-name "$eth_con" || true
    sudo nmcli con modify "$eth_con" connection.autoconnect yes ipv4.method auto ipv6.method ignore ipv4.route-metric 100 || true
    wlan_con=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$WLAN" '$2==d{print $1; exit}')
    if [[ -n "$wlan_con" ]]; then
      sudo nmcli con modify "$wlan_con" connection.autoconnect yes ipv4.method auto ipv6.method ignore ipv4.route-metric 600 || true
    fi
    ip route show || true
    return 0
  fi
  if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    echo "Setting interface metrics in /etc/dhcpcd.conf..."
    DC=/etc/dhcpcd.conf
    sudo grep -q "^interface $ETH$" "$DC" 2>/dev/null || echo -e "\ninterface $ETH\n  metric 100" | sudo tee -a "$DC" >/dev/null
    sudo grep -q "^interface $WLAN$" "$DC" 2>/dev/null || echo -e "\ninterface $WLAN\n  metric 600" | sudo tee -a "$DC" >/dev/null
    sudo systemctl restart dhcpcd || true
    ip route show || true
    return 0
  fi
  echo "No NetworkManager or dhcpcd; skipping route metrics."
}

ensure_failover_routing

# ------------------------------------------------------------
# Docker and Mosquitto prerequisites
# ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing..."
  if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl enable --now docker
  else
    echo "Please install Docker manually."; exit 2
  fi
fi

if ! groups "$USER" | grep -qw docker; then
  echo "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"
  echo "Log out/in or run 'newgrp docker', then re-run this script."
  exit 3
fi

if ! command -v mosquitto >/dev/null 2>&1; then
  echo "Mosquitto not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y mosquitto mosquitto-clients
fi
MOSQ_CONF="/etc/mosquitto/conf.d/allow_all.conf"
if ! grep -q "listener 1883 0.0.0.0" "$MOSQ_CONF" 2>/dev/null; then
  echo "listener 1883 0.0.0.0" | sudo tee "$MOSQ_CONF"
  echo "allow_anonymous true" | sudo tee -a "$MOSQ_CONF"
fi
sudo systemctl enable --now mosquitto
echo "Using local Mosquitto; MQTT_HOST=$MQTT_HOST"

# ------------------------------------------------------------
# Build/run Victron container
# ------------------------------------------------------------
if [[ ! -f requirements.txt || ! -f victron-secrets.env ]]; then
  echo "Missing requirements.txt or victron-secrets.env. Aborting."; exit 1
fi

echo "Building victron_ble2mqtt image..."
docker build -t victron_ble2mqtt:local .

run_victron_container() {
  if [[ "${1-}" == "verify" ]]; then
    echo "Running verification (20s)..."
    local N=victron_ble2mqtt_verify
    docker run -d --name "$N" --network host \
      --env-file victron-secrets.env -e MQTT_HOST="$MQTT_HOST" \
      --privileged -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
      victron_ble2mqtt:local >/dev/null || true
    sleep 20
    docker stop "$N" >/dev/null 2>&1 || true
    docker rm "$N" >/dev/null 2>&1 || true
    echo "Verification complete."; exit 0
  fi
}

if [[ "${1-}" == "--verify" ]]; then
  run_victron_container verify
fi

COMPOSE_FILE="docker-compose.victron.yml"
if docker compose version >/dev/null 2>&1; then
  docker compose -f "$COMPOSE_FILE" up --build -d
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f "$COMPOSE_FILE" up --build -d
else
  if docker ps -a --format '{{.Names}}' | grep -qw victron_ble2mqtt; then
    docker start victron_ble2mqtt >/dev/null || true
  else
    docker run -d --name victron_ble2mqtt --restart unless-stopped \
      --network host \
      --env-file victron-secrets.env -e MQTT_HOST="$MQTT_HOST" \
      --privileged -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
      victron_ble2mqtt:local >/dev/null || true
  fi
fi

# ------------------------------------------------------------
# Home Assistant setup
# ------------------------------------------------------------
HA_TZ="America/Chicago"
HA_CONFIG_DIR="/opt/homeassistant"
if [[ ! -d "$HA_CONFIG_DIR" ]]; then
  sudo mkdir -p "$HA_CONFIG_DIR"
fi
# Ensure we own the HA config dir before writing files
sudo chown -R "$USER":"$USER" "$HA_CONFIG_DIR" || true
if [[ ! -f "$HA_CONFIG_DIR/configuration.yaml" ]]; then
  cat > "$HA_CONFIG_DIR/configuration.yaml" <<'YAML'
homeassistant:
  time_zone: America/Chicago
YAML
fi
# HA 2026+ rejects YAML broker settings. MQTT is a UI config entry after HA starts.
if [[ "${FORCE_HA_MQTT_YAML:-0}" == "1" ]]; then
  echo "[deploy_local] FORCE_HA_MQTT_YAML=1 is ignored: HA 2026+ rejects YAML broker settings."
fi
if docker ps -a --format '{{.Names}}' | grep -qw homeassistant; then
  docker start homeassistant >/dev/null || true
else
  docker run -d --name homeassistant --restart unless-stopped \
    --network host -e TZ="$HA_TZ" -v "$HA_CONFIG_DIR":/config \
    "${HA_IMAGE:-ghcr.io/home-assistant/home-assistant:2026.7.3}" >/dev/null
fi

# Apply HA config changes by restarting the container if it's running
if docker ps --format '{{.Names}}' | grep -qw homeassistant; then
  docker restart homeassistant >/dev/null || true
fi

echo "Waiting for Home Assistant on http://localhost:8123 ..."
for i in {1..30}; do
  if curl -fsS http://localhost:8123 >/dev/null 2>&1; then
    echo "Home Assistant is up: http://localhost:8123"; break
  fi
  sleep 2
done

if [[ "${ENABLE_HA_MQTT_INTEGRATION:-1}" == "1" ]]; then
  echo "[deploy_local] Ensuring Home Assistant MQTT config entry (HA 2026+; not YAML) ..."
  bash "$REPO_ROOT/scripts/ha_enable_mqtt_integration.sh" || echo "[deploy_local] MQTT integration script failed (check HA logs)."
fi

echo "Deployment done. Logs: docker logs -f victron_ble2mqtt"

# ------------------------------------------------------------
# Optional: install/enable Wi‑Fi failover monitor via systemd
# Set ENABLE_FAILOVER_MONITOR=1 in .env to turn this on
# ------------------------------------------------------------
if [[ "${ENABLE_FAILOVER_MONITOR:-0}" == "1" ]]; then
  if pidof systemd >/dev/null 2>&1; then
    if [[ -f systemd/wifi-failover-monitor@.service ]]; then
      echo "Installing wifi-failover-monitor systemd unit..."
      sudo install -m 644 systemd/wifi-failover-monitor@.service /etc/systemd/system/wifi-failover-monitor@.service
      sudo systemctl daemon-reload
      sudo systemctl enable --now "wifi-failover-monitor@${USER}.service" || true
      echo "Failover monitor active. Check: journalctl -u wifi-failover-monitor@${USER}.service -f"
    else
      echo "Unit file missing: systemd/wifi-failover-monitor@.service"
    fi
  else
    echo "System does not run systemd (skipping failover monitor install)."
  fi
fi
