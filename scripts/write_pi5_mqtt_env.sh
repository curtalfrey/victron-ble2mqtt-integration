#!/usr/bin/env bash
# Writes Theengs mqtt.env for the Pi 5. Never prints MQTT_PASSWORD.
# Broker default is .105 (canonical Mosquitto). Override with MQTT_LAN=.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/hosts/pi5/mqtt.env}"
ENV_FILE="${VICTRON_ENV:-$ROOT/.env}"
MQTT_LAN="${MQTT_LAN:-${PI4_MQTT_LAN:-192.168.0.105}}"
exec python3 "$ROOT/scripts/write_theengs_mqtt_env.py" "$ENV_FILE" "$OUT" "$MQTT_LAN"
