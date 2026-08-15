#!/usr/bin/env bash
# Smoke-test Sungold read-only Modbus → MQTT sidecar (run on Pi after USB is connected).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

: "${MQTT_HOST:=127.0.0.1}"
: "${MQTT_PORT:=1883}"
: "${MQTT_TOPIC:=sungold_sph302480a}"
: "${SUNGOLD_SERIAL_DEVICE:=/dev/sungold}"

fail=0
ok() { echo "[smoke] OK: $*"; }
warn() { echo "[smoke] WARN: $*" >&2; }
die() { echo "[smoke] FAIL: $*" >&2; fail=1; }

echo "[smoke] Sungold SPH302480A sidecar smoke test"

if [[ -e "$SUNGOLD_SERIAL_DEVICE" || -e /dev/sungold ]]; then
  ok "serial device present (${SUNGOLD_SERIAL_DEVICE} or /dev/sungold)"
else
  die "no serial device — plug USB and set SUNGOLD_SERIAL_DEVICE in .env"
fi

if docker ps --format '{{.Names}}' | grep -qw sungold_modbus_ro; then
  ok "container sungold_modbus_ro running"
  status="$(docker inspect -f '{{.State.Health.Status}}' sungold_modbus_ro 2>/dev/null || echo unknown)"
  echo "[smoke] health: ${status}"
  if [[ "$status" == "unhealthy" ]]; then
    warn "container unhealthy — check docker logs sungold_modbus_ro (Modbus may not respond until inverter is on)"
  fi
else
  die "container sungold_modbus_ro not running — ENABLE_SUNGOLD=1 && sudo bash scripts/deploy.sh"
fi

if [[ -n "${MQTT_USER:-}" && -n "${MQTT_PASSWORD:-}" ]]; then
  if mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
    -t "${MQTT_TOPIC}/sensor/battery/soc/state" -C 1 -W 15 -v 2>/dev/null; then
    ok "MQTT state topic received (${MQTT_TOPIC}/sensor/battery/soc/state)"
  else
    warn "no MQTT state within 15s — inverter off or Modbus not responding yet"
  fi

  if mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
    -t "homeassistant/sensor/${MQTT_TOPIC}-battery-soc/config" -C 1 -W 5 2>/dev/null | grep -q unique_id; then
    ok "HA discovery config present for battery SOC"
  else
    warn "HA discovery not seen yet (container may still be starting)"
  fi
else
  warn "MQTT_USER/MQTT_PASSWORD unset — skip broker subscribe checks"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "[smoke] FAILED — see docs/SUNGOLD_SPH302480A.md"
  exit 1
fi

echo "[smoke] PASSED (or WARN-only if inverter not yet online)"
exit 0
