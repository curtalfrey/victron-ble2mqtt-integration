# Repository inventory (2026-07)

Quick map of the **current** layout. Supersedes older inventory notes that claimed
empty Compose / Swarm docs.

## Purpose

Raspberry Pi edge stack: Victron BLE advertisements → MQTT (+ Home Assistant
discovery) → Mosquitto (host systemd) + Home Assistant + Dockge. Not a GPU /
Petals worker. See `docs/ALFA_CLUSTER_INTEGRATION.md`.

## Runtime code

| Path | Role |
|------|------|
| `override/victron_ble2mqtt/` | **Production** Python (Compose mounts / `PYTHONPATH` prefers this) |
| `victron_ble2mqtt/` | Package shims / parallel tree (keep in sync until layout unify) |
| `docker-entrypoint.sh` | Builds `user_settings.py` from env + device metadata |
| `Dockerfile` | App image `victron_ble2mqtt:local` |

## Compose / ops

| Path | Role |
|------|------|
| `docker-compose.victron.yml` | BLE bridge container |
| `docker-compose.homeassistant.yml` | HA (**pinned** image tag; see file) |
| `docker-compose.autoheal.yml` | Restarts unhealthy labeled containers |
| `docker-compose.tools.yml` | Watchtower (label-gated; HA has no enable label) |
| `docker-compose.dockge.yml` | Dockge UI |
| `scripts/deploy.sh` | Idempotent Pi installer |
| `systemd/` | Tracked units/timers installed by deploy |
| `dotenv.sample` | Template for host `.env` |

## Docs (prefer these)

| Path | Role |
|------|------|
| `DEPLOY.md` | Operator deploy runbook |
| `docs/ENGINEERING_STANDARDS_PLAN.md` | Standards roadmap |
| `docs/ALFA_CLUSTER_INTEGRATION.md` | Hub / monitoring / Cursor siblings |
| `SECURITY_REMOVE_SECRETS.md` | Secret hygiene |
| `Victron_BLE_to_MQTT_Integration_Setup_Guide.md` | **Legacy** venv/systemd era — prefer `DEPLOY.md` |

## Tests / CI

| Path | Role |
|------|------|
| `tests/` | Unit + MQTT integration tests |
| `.github/workflows/ci.yml` | Ruff + pytest (lints **override** and package) |

## Open follow-ups

- Unify `override/` + `victron_ble2mqtt/` into one package tree.
- Phase 5 threat-model acceptance (`docs/ENGINEERING_STANDARDS_PLAN.md`).
- History purge for previously tracked `ssl/tools.*` (see `SECURITY_REMOVE_SECRETS.md`).
