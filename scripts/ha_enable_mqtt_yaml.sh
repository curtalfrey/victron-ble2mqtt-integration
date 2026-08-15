#!/usr/bin/env bash
# Deprecated: HA 2026+ rejects broker settings in configuration.yaml.
# Use scripts/ha_enable_mqtt_integration.sh instead.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${ROOT}/scripts/ha_enable_mqtt_integration.sh" "$@"
