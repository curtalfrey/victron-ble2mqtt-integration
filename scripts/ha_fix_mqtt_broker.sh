#!/usr/bin/env bash
# Safely retarget Home Assistant's MQTT integration to the local broker (127.0.0.1:1883).
# - Backs up /config/.storage/core.config_entries inside the container
# - Edits only the mqtt entry
# - Optionally restarts HA to apply

set -euo pipefail

HA_CONT=${HA_CONT:-homeassistant}
NEW_HOST=${MQTT_HOST:-127.0.0.1}
NEW_PORT=${MQTT_PORT:-1883}
# Optionally set MQTT username/password (leave empty for anonymous access)
NEW_USER=${MQTT_USER:-}
NEW_PASS=${MQTT_PASSWORD:-}

echo "[ha_fix_mqtt_broker] targeting $HA_CONT mqtt-> ${NEW_HOST}:${NEW_PORT} (user=${NEW_USER:+set}/pass=${NEW_PASS:+set})"

if ! docker ps --format '{{.Names}}' | grep -qx "$HA_CONT"; then
  echo "Container $HA_CONT not running" >&2
  exit 1
fi

TS=$(date +%Y%m%d-%H%M%S)
FILE=/config/.storage/core.config_entries
BAK=/config/.storage/core.config_entries.bak-${TS}

echo "Backing up $FILE to $BAK ..."
docker exec "$HA_CONT" bash -lc "cp -n '$FILE' '$BAK' && ls -l '$BAK'"

echo "Patching MQTT config entries ..."
docker exec -i "$HA_CONT" env \
  NEW_USER="${NEW_USER}" \
  NEW_PASS="${NEW_PASS}" \
  NEW_HOST="${NEW_HOST}" \
  NEW_PORT="${NEW_PORT}" \
  python3 - <<PY
import json, sys
from pathlib import Path
import os
file = Path("/config/.storage/core.config_entries")
data = json.loads(file.read_text())
changed = False
# pick up optional auth from environment
new_user = os.environ.get("NEW_USER")
new_pass = os.environ.get("NEW_PASS")
for e in list(data.get("data",{}).get("entries", [])):
    if e.get("domain") == "mqtt":
        d = e.setdefault("data", {})
        before = (d.get("broker"), d.get("port"))
        d["broker"] = os.environ.get("NEW_HOST") or "127.0.0.1"
        try:
            d["port"] = int(os.environ.get("NEW_PORT") or "1883")
        except Exception:
            d["port"] = 1883
        if new_user:
            d["username"] = new_user
            if new_pass:
                d["password"] = new_pass
        after = (d.get("broker"), d.get("port"))
        print("mqtt entry:", before, "->", after)
        changed = True
if changed:
    file.write_text(json.dumps(data, indent=2, sort_keys=True))
    print("written", file)
else:
    print("no_mqtt_integration_found")
PY

if [[ "${RESTART:-1}" == "1" ]]; then
  echo "Restarting $HA_CONT to apply changes ..."
  docker restart "$HA_CONT" >/dev/null
  echo "Restarted."
fi

echo "Done."
