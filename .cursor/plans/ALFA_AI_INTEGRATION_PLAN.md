# ALFa AI Integration Plan — victron-ble2mqtt-integration (Wave 5d)

> Doc-first, single best path. **`/home/ansible/victron-ble2mqtt-integration`**
> is a production Raspberry-Pi-edge bridge: Victron BLE → MQTT → Home Assistant.
> This plan adds **advisory-only ALFa AI scripts on `.105`** that read telemetry
> via Home Assistant's Recorder REST API, summarize battery health, detect
> anomalies, and suggest charge-cycle advisories. **AI never controls Victron
> hardware.** Brain on `.111`; LAN URLs.

---

## 0. Authoritative References

### ALFa AI canonical docs

1. `/home/ansible/alfa-ai/docs/CURRENT_CAPABILITIES_AND_USE_CASES.md`
2. `/home/ansible/alfa-ai/docs/PORT_ASSIGNMENTS.md`
3. `/home/ansible/alfa-ai/deploy/litellm_config.yaml`

### Sibling Wave plans

4. `/home/ansible/scripts/.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` — Wave 4c libs (hard dep)
5. `/home/ansible/monitoring/.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` — Wave 4a Prometheus pattern
6. `/home/ansible/.cursor/plans/ALFA_AI_INTEGRATION_PLAN_HOST_105.md` — Wave 1 host contract
7. `/home/ansible/myai-workspace/.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` — fine-tune target

### This repo (discovered)

8. `victron-ble2mqtt-integration/docker-compose.victron.yml` — BLE-MQTT bridge container
9. `victron-ble2mqtt-integration/docker-compose.homeassistant.yml` — HA container
10. `victron-ble2mqtt-integration/DEPLOY.md` — Pi deployment runbook
11. `victron-ble2mqtt-integration/AGENTS.md` — existing agent guidance
12. `victron-ble2mqtt-integration/dashboards/` — Grafana dashboards (existing telemetry pattern)
13. `victron-ble2mqtt-integration/swarm/` — Docker Swarm topology
14. `victron-ble2mqtt-integration/.git/` — already a git repo

### Workspace rules

15. `/home/ansible/.cursorrules`
16. `/home/ansible/.cursor/rules/pre-install-research.mdc`
17. `/home/ansible/.cursor/rules/operator-wait-for-output.mdc`
18. `/home/ansible/.cursor/rules/deployment-process-ownership.mdc`

### Industry standards

19. [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/)
20. [Home Assistant Recorder](https://www.home-assistant.io/integrations/recorder/)
21. [MQTT v3.1.1](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/)

---

## 1. Discovered State + Service Contract

### 1.1 Discovery summary

| Check | Result |
|-------|--------|
| Stack | Python BLE bridge + Mosquitto MQTT + Home Assistant + Grafana |
| Edge device | Raspberry Pi (BLE in range of Victron devices) |
| Telemetry | HA Recorder (SQLite/MariaDB) + MQTT topics + Grafana |
| Existing AI | None |
| `.git/` | Present |
| Current monitoring | Prometheus scraping HA exporter (per `DEPLOY.md`) |

### 1.2 Mission / audience

| Attribute | Value |
|-----------|-------|
| Mission | Bridge Victron BLE telemetry into Home Assistant; expose advisory AI for battery health monitoring |
| Audience | Operators (RV/off-grid owners) — read-only advisories |
| Trust zone | `operator_internal` only |
| Default model alias | `agent` for summaries; `code` for anomaly explanation |

### 1.3 Service contract

| Surface | URL | Auth | Notes |
|---------|-----|------|-------|
| LiteLLM (from `.105`) | `http://192.168.0.111:8413` | Bearer | `host105-ai.env` |
| Home Assistant REST | `http://<pi-ip>:8123/api/` | Long-lived token | Operator-provisioned, stored on `.105` |
| HA Recorder query | `http://<pi-ip>:8123/api/history/period/` | Bearer | Read-only |
| MQTT broker | `<pi-ip>:1883` | Per HA setup | Not used by AI scripts |
| Telemetry sink | `host105_ops_activity_log` (`metadata.source=victron`) | Docker exec | Wave 1/4c |

**Hardware Safety Disclaimer (mandatory on every AI output):**

> "AI-generated battery and charge-cycle advisory only. Not a substitute for
> Victron official documentation, manufacturer specifications, or qualified
> electrician guidance. Do not act on these advisories without verifying
> against Victron device manuals. AI does not control any Victron hardware."

---

## 2. Integration Surfaces

### 2.1 Battery health summary (`operator_internal`)

**Single path:** `bin/victron-ask.sh [--days 7]`

1. Query HA REST `/api/history/period/` for last N days of Victron entities (voltage, current, SOC, temperature, charge cycles).
2. Compute basic stats (min/max/avg, deltas).
3. Redact via Wave 4c `redact.sh` (defense in depth — minimal PII risk but consistent posture).
4. Send to LiteLLM `agent` with a battery-health summary prompt that includes the mandatory disclaimer.
5. Print verdict to stdout; log to `host105_ops_activity_log`.

### 2.2 Anomaly detection (`operator_internal`)

**Single path:** `bin/victron-anomaly.sh`

Detects:
- SOC drop > 20% in <1 hour
- Voltage below floor (configurable per battery chemistry)
- Temperature outside operating range
- Charge cycle count above expected

Sends event details to LiteLLM `code` alias for plain-English explanation + suggested operator action.

**Does not** automatically alert; writes to `host105_ops_activity_log` for Wave 4b n8n pickup (deferred).

### 2.3 Charge cycle advisory (`operator_internal`)

**Single path:** `bin/victron-cycle-advisor.sh`

Weekly oneshot:
- Reads cycle count + DoD history.
- Compares against chemistry profile (LiFePO4 / lead-acid / etc., operator-supplied in `config/batteries.yml`).
- Outputs `library/advisories/<date>.md` with mandatory disclaimer.

### 2.4 mqtt_exporter deployment (Wave 4a coordination)

Land `mqtt_exporter` container (Prometheus scrape target) in `docker-compose.victron.yml` so monitoring stack (Wave 4a) can alert on the same metrics. AI scripts and Prometheus see consistent data.

### 2.5 Explicit non-goals

- ❌ AI controls any Victron device (BMS, MPPT, inverter)
- ❌ AI auto-applies charge profile changes
- ❌ Public-facing UI
- ❌ Running ALFa AI on the Pi (edge has no LLM)
- ❌ Storing raw BLE packets in `host105_ops_activity_log`

---

## 3. File-Level Plan

| Path | Action | Description |
|------|--------|-------------|
| `.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` | NEW | This plan |
| `docs/ALFA_AI_HOW_TO_USE.md` | NEW | Operator guide |
| `AGENTS.md` | EDIT | Add ALFa AI breadcrumb, point to plan |
| `config/batteries.yml` | NEW | Operator-supplied chemistry/profile |
| `config/ha_endpoint.env.example` | NEW | HA URL + token template |
| `bin/victron-ask.sh` | NEW | Battery health summary |
| `bin/victron-anomaly.sh` | NEW | Anomaly detector |
| `bin/victron-cycle-advisor.sh` | NEW | Weekly cycle advisory |
| `bin/lib/ha_client.sh` | NEW | HA REST helper |
| `docker-compose.victron.yml` | EDIT | Add `mqtt_exporter` container |
| `dashboards/victron-ai-overview.json` | NEW | Grafana panel referencing AI advisory rows |
| `systemd/victron-cycle-advisor.{service,timer}` | NEW | Weekly Sun 04:00 local on `.105` |
| `tests/test_ha_client.sh` | NEW | Mock HA fixtures |

---

## 4. Staged Rollout

### Stage 0 — Preflight

```bash
set -euo pipefail
curl -fsS http://192.168.0.111:8413/health/liveliness
test -f /home/ansible/.config/host105-ai.env
# Operator-provided:
test -n "${HA_URL:-}" -a -n "${HA_TOKEN:-}"
curl -fsS -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/" >/dev/null
```

Operator provides:
- Pi IP / hostname
- HA long-lived access token
- Battery chemistry profile YAML
- Voltage floor / SOC floor per battery

### Stage 1 — `bin/victron-ask.sh` + battery profile

Land script + `config/batteries.yml` template. Operator fills in. Smoke test on 7-day window.

### Stage 2 — Anomaly script

Land `bin/victron-anomaly.sh`. Run manually; verify entries in `host105_ops_activity_log`.

### Stage 3 — Cycle advisor + systemd timer

Install timer on `.105` (NOT on Pi). Weekly oneshot writes advisory markdown.

### Stage 4 — mqtt_exporter + Grafana panel

Deploy `mqtt_exporter` container; add Grafana panel; verify Prometheus scrape.

### Stage 5 — Fine-tune export

Advisory outputs feed `host105_ops_activity_log` with `metadata.source=victron` → Wave 5f federated pipeline.

---

## 5. Risks / Rollback

| Risk | Mitigation | Rollback |
|------|------------|----------|
| AI misleads on battery state | Mandatory disclaimer on every output; advisory only | Disable scripts |
| HA token leak in logs | Never log token; redact env in script outputs | Rotate token |
| AI suggests dangerous action | Plan forbids hardware control; manual operator gate on every action | Operator audits advisory log |
| Brain down | Scripts exit gracefully with clear message | N/A |
| `mqtt_exporter` not yet researched | Stage 4 pre-install research per workspace rule | Skip Stage 4; manual Grafana |
| Wave 4c lib missing | Stage 1 blocked or use temp regex | Replace when lib lands |

---

## 6. Validation & Evaluation

| Test | Method | Gate |
|------|--------|------|
| HA reachability | Stage 0 curl | 200 |
| Disclaimer presence | Every output | Disclaimer string present |
| Brain down graceful | Stop LiteLLM, run scripts | Clean exit, no crash |
| Telemetry write | One advisory | One `host105_ops_activity_log` row |
| Cycle advisor schedule | After Stage 3 install | `systemctl list-timers` shows next run |

---

## 7. Resolved / Open Decisions

### Resolved

| Decision | Choice |
|----------|--------|
| AI never controls Victron | Locked |
| Disclaimer | Mandatory on every output |
| Where scripts live | `.105` only (not Pi) |
| Telemetry source | HA Recorder REST + future mqtt_exporter |
| Schedule for cycle advisor | Weekly Sun 04:00 local |
| Wave 4a coordination | `mqtt_exporter` for shared metrics |

### Open (operator must supply)

1. Pi static IP / hostname (for `HA_URL`)
2. HA entity_id map for Victron sensors (varies per install)
3. Voltage floor / SOC floor per battery chemistry
4. Whether to deploy `mqtt_exporter` at Stage 1 or defer to Stage 4
