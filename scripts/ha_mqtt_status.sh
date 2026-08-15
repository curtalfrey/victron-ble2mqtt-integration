#!/usr/bin/env bash
# shellcheck disable=SC2016
# Show Home Assistant MQTT configuration status (YAML vs UI integration) and key details.
# - Prints whether YAML-based MQTT is enabled (which blocks UI add flow)
# - Prints MQTT integration entry from /config/.storage/core.config_entries (inside HA)
# - Summarizes broker/port/username settings
set -euo pipefail

HA_CONT=${HA_CONT:-homeassistant}
HA_CONFIG_DIR=${HA_CONFIG_DIR:-/opt/homeassistant}

echo "== containers =="
docker ps --format '{{.Names}}\t{{.Status}}' | sed -n '1,100p'

echo
echo "== YAML MQTT in ${HA_CONFIG_DIR}/configuration.yaml =="
if [[ -f "${HA_CONFIG_DIR}/configuration.yaml" ]]; then
  grep -nE '^mqtt:|mqtt: *!include' "${HA_CONFIG_DIR}/configuration.yaml" || echo "(no mqtt stanza found)"
else
  echo "(configuration.yaml not found at ${HA_CONFIG_DIR})"
fi

if [[ -f "${HA_CONFIG_DIR}/mqtt.yaml" ]]; then
  echo
  echo "== ${HA_CONFIG_DIR}/mqtt.yaml (summary) =="
  awk -F: '/^(broker|port|username|password)/{print $1 ":" $2}' "${HA_CONFIG_DIR}/mqtt.yaml" || true
fi

if docker ps --format '{{.Names}}' | grep -qw "${HA_CONT}"; then
  echo
  echo "== core.config_entries mqtt entry (inside ${HA_CONT}) =="
  docker exec "${HA_CONT}" bash -lc "python3 - <<'PY'\nimport json\nfrom pathlib import Path\nfile=Path('/config/.storage/core.config_entries')\ntry:\n  data=json.loads(file.read_text())\n  entries=[e for e in data.get('data',{}).get('entries',[]) if e.get('domain')=='mqtt']\n  if not entries:\n    print('no mqtt entry')\n  else:\n    e=entries[0]\n    d=e.get('data',{})\n    print('title=', e.get('title'), 'source=', e.get('source'))\n    print('broker=', d.get('broker'), 'port=', d.get('port'), 'username_set=', bool(d.get('username')))\nexcept Exception as ex:\n  print('error:', ex)\nPY" || true
else
  echo
  echo "Home Assistant container (${HA_CONT}) is not running."
fi

echo
echo "== Hint =="
echo "If YAML is present, disable it: run scripts/ha_disable_yaml_mqtt.sh and restart HA."
echo "To enable MQTT (HA 2026+): run scripts/ha_enable_mqtt_integration.sh"
echo "If an MQTT integration exists, configure it in the UI (Devices & Services). To re-add fresh, run scripts/ha_remove_mqtt_integration.sh then run ha_enable_mqtt_integration.sh."
