# ALFa AI advisory tools — deferred

**Status (2026-07):** The operator scripts described in the former Wave plan
(`bin/victron-ask.sh`, `bin/victron-anomaly.sh`, `bin/victron-cycle-advisor.sh`,
`config/batteries.yml`, and related systemd units) are **not shipped in this
repo**. Do not follow older copies of this guide that call those paths.

## What is live today

| Surface | Location |
|---------|----------|
| Pi edge stack (BLE → MQTT → HA) | `DEPLOY.md`, `scripts/deploy.sh` |
| Cluster / hub integration | `docs/ALFA_CLUSTER_INTEGRATION.md` |
| Planned AI advisory design | `.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` |
| Engineering roadmap | `docs/ENGINEERING_STANDARDS_PLAN.md` |

## Safety (unchanged when tools land)

AI advisory output must remain **read-only**: never `mqtt_publish` back to Victron
or write control commands to Home Assistant. Any future battery / cycle summary
must include a hardware safety disclaimer and point operators at Victron manuals.

## When tooling is added

1. Update this doc with real paths and prerequisites.
2. Add `config/batteries.yml.example` (no site-specific secrets).
3. Keep scripts out of the Pi hot path unless explicitly designed for on-device use.
