# Operator How-To — victron-ble2mqtt-integration ALFa AI

## What this gives you

| Tool | Purpose |
|------|---------|
| `victron-ask.sh` | Plain-English battery health summary from HA Recorder data |
| `victron-anomaly.sh` | Voltage/SOC/temperature anomaly detection + explanation |
| `victron-cycle-advisor.sh` | Weekly charge-cycle advisory based on chemistry profile |

All AI outputs include the **mandatory Hardware Safety Disclaimer**:

> "AI-generated battery and charge-cycle advisory only. Not a substitute for Victron official documentation, manufacturer specifications, or qualified electrician guidance. Do not act on these advisories without verifying against Victron device manuals. AI does not control any Victron hardware."

**AI never controls Victron devices.** Read-only advisory only.

## Prerequisites

1. Brain healthy: `curl -fsS http://192.168.0.111:8413/health/liveliness`.
2. Pi reachable from `.105`: ping its IP.
3. HA long-lived access token in `/home/ansible/.config/victron-ai.env`:

   ```bash
   HA_URL=http://<pi-ip>:8123
   HA_TOKEN=<long-lived-token>
   ```

4. Wave 4c shared libs at `/home/ansible/scripts/alfa-ai/lib/{common,redact,log}.sh`.
5. Battery chemistry profile populated in `config/batteries.yml`.

## Run a battery health summary

```bash
cd /home/ansible/victron-ble2mqtt-integration
bash bin/victron-ask.sh --days 7
```

Output: stdout summary with disclaimer; row in `host105_ops_activity_log`.

## Check for anomalies

```bash
bash bin/victron-anomaly.sh
```

Scans last 24h; flags voltage/SOC/temperature deviations from chemistry profile. Each anomaly explained in plain English; logged.

## Enable weekly cycle advisory

```bash
sudo install -m 644 systemd/victron-cycle-advisor.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now victron-cycle-advisor.timer
```

Sundays 04:00 local → writes `library/advisories/<date>.md`.

## What NOT to do

- ❌ Do not let any script send a `mqtt_publish` or write back to HA.
- ❌ Do not remove the Hardware Safety Disclaimer.
- ❌ Do not run these scripts on the Pi — they belong on `.105`.
- ❌ Do not use AI advisories as a sole input to charging decisions; verify against Victron manuals.

## Related docs

- `.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md`
- `/home/ansible/scripts/.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` — shared libs
- `/home/ansible/monitoring/.cursor/plans/ALFA_AI_INTEGRATION_PLAN.md` — coordinated Prometheus alerts
- `DEPLOY.md` — Pi deployment runbook
- `dashboards/` — Grafana dashboards
