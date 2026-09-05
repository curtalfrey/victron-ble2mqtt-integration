#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Load env for MQTT auth
if [[ -f ./.env ]]; then set -a; . ./.env; set +a; fi

OUT_DIR="$REPO/_diag"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$OUT_DIR/diag_${STAMP}.log"
LATEST="$OUT_DIR/latest.log"

exec > >(tee -a "$OUT_FILE") 2>&1

echo "== DIAG START $(date -Is) =="
echo "== ENV (masked) =="
echo "MQTT_USER=${MQTT_USER:-}"
echo "MQTT_PASSWORD=****"
echo "MQTT_HOST=${MQTT_HOST:-}"
echo "MQTT_PORT=${MQTT_PORT:-}"

echo
echo "== docker ps =="
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | sed -n '1,200p' || true

echo
echo "== broker port 1883 listening =="
ss -lntp | grep -E ":1883\s" || echo "(not found)"

echo
echo "== HA MQTT status =="
bash scripts/ha_mqtt_status.sh || true

echo
echo "== retained probe (auth) =="
TS=$(date +%s)
if mosquitto_pub -h 127.0.0.1 -p 1883 -u "${MQTT_USER:-}" -P "${MQTT_PASSWORD:-}" -t test/probe -m "probe-$TS" -r; then
  echo "publish ok"
else
  echo "publish failed ($?)"
fi
if mosquitto_sub -h 127.0.0.1 -p 1883 -u "${MQTT_USER:-}" -P "${MQTT_PASSWORD:-}" -t test/probe -C 1 -W 5 -v; then
  echo "subscribe ok"
else
  echo "subscribe timed out or failed ($?)"
fi

echo
echo "== HA birth topic (15s) =="
if mosquitto_sub -h 127.0.0.1 -p 1883 -u "${MQTT_USER:-}" -P "${MQTT_PASSWORD:-}" -t 'homeassistant/status' -C 1 -W 15 -v; then
  echo "birth observed"
else
  echo "no birth observed (may already be online)"
fi

echo
echo "== Discovery topics (2 msgs, 20s) =="
if mosquitto_sub -h 127.0.0.1 -p 1883 -u "${MQTT_USER:-}" -P "${MQTT_PASSWORD:-}" -t 'homeassistant/+/+/config' -C 2 -W 20 -v; then
  echo "discovery observed"
else
  echo "no discovery observed (timeout)"
fi

echo
echo "== Victron container MQTT env =="
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' victron_ble2mqtt 2>/dev/null \
  | grep -E 'MQTT_HOST|MQTT_PORT|MQTT_USER|MQTT_PASSWORD' \
  | sed -E 's/^(MQTT_PASSWORD=).*/\1****/' \
  || echo "victron container not found"

echo
echo "== Recent logs: victron (last 120s) =="
docker logs --since 120s victron_ble2mqtt 2>&1 | tail -n 200 || echo "no victron logs"

echo
echo "== Recent logs: homeassistant (last 120s) =="
docker logs --since 120s homeassistant 2>&1 | tail -n 200 || echo "no homeassistant logs"

echo "== DIAG END $(date -Is) =="

ln -sf "$(basename "$OUT_FILE")" "$LATEST"
echo "Saved: $OUT_FILE"
