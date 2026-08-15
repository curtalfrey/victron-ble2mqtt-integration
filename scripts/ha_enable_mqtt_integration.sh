#!/usr/bin/env bash
# Enable Home Assistant MQTT broker integration (HA 2026+ — UI/config entry only; YAML broker is invalid).
# - Removes legacy mqtt: !include mqtt.yaml from configuration.yaml
# - Creates an mqtt config entry pointing at the local Mosquitto broker (127.0.0.1:1883)
# - Restarts Home Assistant
#
# Credentials: MQTT_USER / MQTT_PASSWORD from environment or repo .env (same as Mosquitto).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HA_CONT=${HA_CONT:-homeassistant}
HA_CONFIG_DIR=${HA_CONFIG_DIR:-/opt/homeassistant}
RESTART=${RESTART:-1}

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

MQTT_HOST=${MQTT_HOST:-127.0.0.1}
# HA runs on the Pi host network; always use loopback for the broker socket.
MQTT_BROKER=127.0.0.1
MQTT_PORT=${MQTT_PORT:-1883}
MQTT_USER=${MQTT_USER:-}
MQTT_PASSWORD=${MQTT_PASSWORD:-}

echo "[ha_enable_mqtt_integration] HA container: ${HA_CONT}"
echo "[ha_enable_mqtt_integration] broker: ${MQTT_BROKER}:${MQTT_PORT} user=${MQTT_USER:+set}"

if ! docker ps --format '{{.Names}}' | grep -qw "${HA_CONT}"; then
  echo "Home Assistant container (${HA_CONT}) is not running." >&2
  exit 1
fi

conf="${HA_CONFIG_DIR}/configuration.yaml"
if [[ -f "${conf}" ]]; then
  if grep -qE '^mqtt:|^mqtt: *!include' "${conf}"; then
    echo "[ha_enable_mqtt_integration] Removing legacy YAML mqtt stanza from ${conf} ..."
    cp -a "${conf}" "${conf}.bak.$(date +%s)"
    sed -i -e '/^mqtt:/d' -e '/^mqtt: *!include/d' "${conf}"
  fi
fi

mqtt_yaml="${HA_CONFIG_DIR}/mqtt.yaml"
if [[ -f "${mqtt_yaml}" ]]; then
  echo "[ha_enable_mqtt_integration] Disabling ${mqtt_yaml} ..."
  mv -f "${mqtt_yaml}" "${mqtt_yaml}.disabled.$(date +%s)"
fi

TS=$(date +%Y%m%d-%H%M%S)
FILE=/config/.storage/core.config_entries
BAK="/config/.storage/core.config_entries.bak-${TS}"

echo "[ha_enable_mqtt_integration] Backing up config entries ..."
docker exec "${HA_CONT}" bash -lc "cp -n '${FILE}' '${BAK}'"

docker exec -i "${HA_CONT}" env \
  MQTT_BROKER="${MQTT_BROKER}" \
  MQTT_PORT="${MQTT_PORT}" \
  MQTT_USER="${MQTT_USER}" \
  MQTT_PASSWORD="${MQTT_PASSWORD}" \
  python3 - <<'PY'
import json
import os
import uuid
from pathlib import Path

file = Path("/config/.storage/core.config_entries")
data = json.loads(file.read_text())
entries = data.setdefault("data", {}).setdefault("entries", [])

existing = [e for e in entries if e.get("domain") == "mqtt"]
if existing:
    e = existing[0]
    d = e.setdefault("data", {})
    d["broker"] = os.environ["MQTT_BROKER"]
    d["port"] = int(os.environ["MQTT_PORT"])
    d["protocol"] = "5"
    user = os.environ.get("MQTT_USER") or None
    password = os.environ.get("MQTT_PASSWORD") or None
    if user:
        d["username"] = user
        d["password"] = password
    else:
        d.pop("username", None)
        d.pop("password", None)
    e["version"] = 2
    e["minor_version"] = 1
    e.setdefault("discovery_keys", {})
    e.setdefault("subentries", [])
    print("updated existing mqtt entry:", e.get("entry_id"))
else:
    entry = {
        "created_at": "1970-01-01T00:00:00.000000+00:00",
        "data": {
            "broker": os.environ["MQTT_BROKER"],
            "port": int(os.environ["MQTT_PORT"]),
            "protocol": "5",
        },
        "discovery_keys": {},
        "disabled_by": None,
        "domain": "mqtt",
        "entry_id": str(uuid.uuid4()),
        "minor_version": 1,
        "modified_at": "1970-01-01T00:00:00.000000+00:00",
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": os.environ["MQTT_BROKER"],
        "unique_id": None,
        "version": 2,
    }
    user = os.environ.get("MQTT_USER") or None
    password = os.environ.get("MQTT_PASSWORD") or None
    if user:
        entry["data"]["username"] = user
        entry["data"]["password"] = password
    entries.append(entry)
    print("created mqtt entry:", entry["entry_id"])

# HA 2026+ requires discovery_keys and subentries on every entry.
for entry in entries:
    if "discovery_keys" not in entry:
        entry["discovery_keys"] = {}
    if "subentries" not in entry:
        entry["subentries"] = []

file.write_text(json.dumps(data, indent=2, sort_keys=True))
print("written", file)
PY

if [[ "${RESTART}" == "1" ]]; then
  echo "[ha_enable_mqtt_integration] Restarting ${HA_CONT} ..."
  docker restart "${HA_CONT}" >/dev/null
  echo "[ha_enable_mqtt_integration] Waiting for HA healthy ..."
  ha_ok=0
  for i in $(seq 1 60); do
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${HA_CONT}" 2>/dev/null || true)"
    if [[ "${health}" == "healthy" ]] && curl -fsS http://127.0.0.1:8123 >/dev/null 2>&1; then
      echo "[ha_enable_mqtt_integration] Home Assistant is healthy."
      ha_ok=1
      break
    fi
    if docker logs --since 20s "${HA_CONT}" 2>&1 | grep -q "KeyError: '"; then
      echo "[ha_enable_mqtt_integration] HA is crash-looping (KeyError in logs). Aborting." >&2
      exit 1
    fi
    sleep 2
  done
  if [[ "${ha_ok}" != "1" ]]; then
    echo "[ha_enable_mqtt_integration] Home Assistant did not become healthy." >&2
    exit 1
  fi
fi

echo "[ha_enable_mqtt_integration] MQTT entities:"
docker exec "${HA_CONT}" python3 - <<'PY'
import json
j = json.load(open("/config/.storage/core.entity_registry"))
mqtt = [e for e in j["data"]["entities"] if e.get("platform") == "mqtt"]
pi4 = [e for e in mqtt if "pi4" in (e.get("unique_id") or "").lower() or "pi4" in e.get("entity_id", "")]
print("mqtt entities:", len(mqtt))
print("pi4 mqtt entities:", len(pi4))
for e in sorted(pi4, key=lambda x: x.get("entity_id", ""))[:12]:
    print(" ", e.get("entity_id"))
PY

echo "[ha_enable_mqtt_integration] Done."
