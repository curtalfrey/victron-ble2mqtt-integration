#!/usr/bin/env bash
# Run on the Pi 4 (or any host with this repo's .env). Writes Theengs mqtt.env
# for the Pi 5. Never prints MQTT_PASSWORD.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/hosts/pi5/mqtt.env}"
ENV_FILE="${VICTRON_ENV:-$ROOT/.env}"
PI4_MQTT_LAN="${PI4_MQTT_LAN:-192.168.0.223}"
exec python3 "$ROOT/scripts/write_theengs_mqtt_env.py" "$ENV_FILE" "$OUT" "$PI4_MQTT_LAN"
