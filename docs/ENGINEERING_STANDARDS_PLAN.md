# Engineering standards implementation plan

This document is the **single roadmap** for aligning **victron-ble2mqtt-integration** with maintainable, auditable practices grounded in **official manuals** (Docker, Docker Compose, systemd, Debian packaging, Python packaging) and common **industry defaults** (Twelve-Factor config, least-privilege secrets, CI gates).

**Scope:** deploy scripts, Compose stacks, systemd units, Python bridge, shell helpers, and overlap with **monitoring** (`monitoring/hosts/pi4-victron/README.md`) after operational changes.

**Non-goals:** turning the Pi into a Petals/GPU worker; changing Victron protocol behavior unless required for reliability.

---

## Phase 0 — Baseline and references (no code churn)

**Status:** Done — **`DEPLOY.md` Notes** now include a **sources of truth** bullet (Compose paths, Mosquitto/systemd, secret files). Manual anchors remain as listed below.

**Deliverables**

- Short **“sources of truth”** note in `DEPLOY.md` or `README.md`: which file owns Mosquitto config, which Compose files Dockge includes, where secrets live (`.env`, `victron-secrets.env`, `/etc/mosquitto/watchdog.env`).
- Confirm **manual anchors** the repo claims to follow:
  - [Docker Compose — Compose file reference](https://docs.docker.com/reference/compose-file/) (`healthcheck`, `restart`, logging).
  - [Docker — Configure logging drivers](https://docs.docker.com/engine/logging/configure/) (json-file rotation already used — keep consistent limits across stacks).
  - [systemd.service — Restart=](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) for native `mosquitto.service`.
  - [Twelve-Factor — Config](https://12factor.net/config) for env vs baked secrets.

**Acceptance:** Maintainer can answer “where do I change X?” without reading `deploy.sh` end-to-end.

---

## Phase 1 — Container supervision (replace overlapping watchdogs with standard patterns)

**Status:** Done — **`docker-compose.autoheal.yml`** (`willfarrell/autoheal:1.2.0`), **`autoheal=true`** labels on **`homeassistant`** and **`victron_ble2mqtt`**, **`ENABLE_AUTOHEAL=1`** (default), **`ENABLE_HA_WATCHDOG=0`** (default); **`deploy.sh`** disables legacy **`ha-watchdog.timer`** on redeploy when watchdog off; **`ENABLE_HA_WATCHDOG=1`** remains documented legacy path.

**Verification:** `docker compose … config` for **`docker-compose.autoheal.yml`**, **`docker-compose.victron.yml`**, **`docker-compose.homeassistant.yml`**; **`docker compose up -d`** for **`autoheal`** succeeds on target Docker host. Full wedged-container drill remains operator QA on the Pi (**`DEPLOY.md`**).

**Current state**

- `docker-compose.homeassistant.yml` already defines a **`healthcheck`** (HTTP on port 8123).
- `docker-compose.victron.yml` defines a **`healthcheck`** (import smoke).
- Compose **`restart: unless-stopped`** only restarts on **container exit**, not on **`unhealthy`** ([healthcheck semantics](https://docs.docker.com/reference/compose-file/services/#healthcheck)).
- **`scripts/ha-watchdog.sh`** + **`ha-watchdog.timer`** duplicate HTTP liveness outside Compose.

**Industry-aligned direction**

1. **Introduce a single “unhealthy container recovery” path** for Docker-managed services:
   - Add a small **`autoheal`** (or equivalent) service per [common Compose patterns](https://github.com/willfarrell/docker-autoheal): mount **read-only** Docker socket, **`AUTOHEAL_CONTAINER_LABEL=all`** or label only `homeassistant` and `victron_ble2mqtt`, set sane poll interval (e.g. 30–60s).
   - Add Compose labels on services that should be restarted when unhealthy (avoid restarting unrelated stacks).

2. **After autoheal is proven on the Pi**, make **`ENABLE_HA_WATCHDOG` default `0`** (or remove install path) so HTTP probing happens **once** (Compose healthcheck + autoheal), not twice per minute from systemd.

3. **Keep MQTT broker watchdog until Mosquitto supervision is equivalent or better:**
   - Mosquitto runs under **systemd**, not Compose; `Restart=on-failure` / `Restart=always` handles **process exit**, not **wedged broker**.
   - Options (pick **one** in implementation):
     - **A (minimal change):** Add a **drop-in** for `mosquitto.service` with `Restart=always` and tight `StartLimitIntervalSec` / `StartLimitBurst` to avoid restart storms; **retain** `mqtt-watchdog` until metrics show no false positives.
     - **B (larger):** Run Mosquitto in Compose with **`healthcheck`** (subscribe to `$SYS/broker/uptime`) + autoheal — only if operator accepts broker-in-Docker operational model on this hardware.

**Manual alignment:** Docker documents **HEALTHCHECK** for images; Compose **`healthcheck`** is the stack-level equivalent. Recovery on **`unhealthy`** is **not** Compose core behavior — autoheal (or an orchestrator) is the usual supplement.

**Acceptance**

- With HA intentionally wedged (simulate failure), **container becomes healthy → unhealthy → restarted** without relying on `ha-watchdog.timer`.
- Documentation lists **`ENABLE_HA_WATCHDOG=1`** only as legacy escape hatch.
- No duplicate HTTP probes unless justified (document why).

---

## Phase 2 — `deploy.sh` structure and systemd units (maintainability)

**Status:** Done — **`systemd/docker-prune.{service,timer}`**, **`systemd/mqtt-watchdog.{service,timer}`**, **`scripts/mqtt-watchdog.sh`** are tracked; **`deploy.sh`** installs via **`install -m`** (no inline heredocs for those units). **`vscode-server-cleanup`**, **`ha-watchdog`**, **`wifi-failover-monitor`** were already tracked templates where applicable.

**Problem:** Inline heredocs for units (e.g. `mqtt-watchdog`, `docker-prune`) are hard to review, diff, and validate.

**Direction**

- Move generated units to **`systemd/*.service` / `systemd/*.timer`** in the repo (same pattern as `ha-watchdog.*`).
- `deploy.sh` **installs** files with `install -m`, optionally **`systemctl edit --full`** only when templating user/path is required.
- Run **`shellcheck`** on all `scripts/*.sh` in CI (Phase 4); fix warnings in deploy paths touched by Phase 1–2.

**Acceptance:** Every timer/service under `/etc/systemd/system/` that this repo owns has a **matching tracked file** under `systemd/` or `scripts/` with a clear header comment.

---

## Phase 3 — Python bridge quality (packaging, typing, tests)

**Status:** Partial — **`[dependency-groups] dev`** added to **`pyproject.toml`**; Ruff config migrated to **`[tool.ruff.lint]`**; **`victron_ble2mqtt/test_helpers.py`** fixed for Ruff; CI runs **`pytest`** + **`ruff check victron_ble2mqtt`** (tests lint deferred — many intentional lazy imports).

**Direction** (incremental, highest ROI first)

1. **Extend existing `pyproject.toml`:** add or consolidate **dev** dependency groups (`pytest`, `ruff`, optional `mypy`) per [Python packaging guidance](https://packaging.python.org/).
2. **`ruff`** (or `flake8` + `black` — pick **one** formatter/linter family): enforce on `victron_ble2mqtt/` and `tests/`.
3. **`pytest`** in CI for offline-safe tests; mark BLE/integration tests as **`@pytest.mark.integration`** and skip by default on CI if hardware required.
4. **Logging:** use **`logging`** module with structured context where helpful; avoid **`print`** in hot paths (align with Docker json-file logging).

**Acceptance:** CI fails on lint regressions; `pytest` passes without Pi BLE.

---

## Phase 4 — CI/CD pipeline (GitHub Actions or equivalent)

**Status:** Minimal workflow added — **`.github/workflows/ci.yml`** (Python 3.11, **`requirements.lock`**, Ruff on **`victron_ble2mqtt/`**, pytest **`tests/`**). **`CONTRIBUTING.md`** mirrors local commands.

**Minimal workflow**

- **shellcheck** → `scripts/**/*.sh`
- **pytest** → `tests/` (non-integration)
- **docker compose config** validation → `docker compose ... config` for each tracked compose file (catches YAML/schema drift)
- Optional **hadolint** `Dockerfile`

**Acceptance:** PRs show green checks; contributors see commands mirrored in `CONTRIBUTING.md` (short).

---

## Phase 5 — Security and operations (OWASP-style hygiene for edge)

**Status:** Open — secrets are gitignored (`.gitignore` covers `victron-secrets.env` / `ha-discovery.env`; only `.example` files tracked, see `SECURITY_REMOVE_SECRETS.md`), but the threat-model paragraph, `chmod 600` documentation, and `set -x` credential audit below are not done.

**Direction**

- **Secrets:** document **`chmod 600`** for `.env`, `victron-secrets.env`, `/etc/mosquitto/watchdog.env`; never log passwords (audit `deploy.sh` / scripts for `set -x` in credential sections).
- **Docker socket:** autoheal (if added) gets **read-only** socket mount; document blast radius.
- **Watchtower:** already label-gated — document required labels for production containers to avoid surprise upgrades.
- **Unattended upgrades / prune timers:** ensure **`docker-prune`** filters match retention policy and **do not** prune volumes needed by HA (`DEPLOY.md` already mentions conservative prune — keep explicit).

**Acceptance:** Threat-model paragraph in `DEPLOY.md` (Pi LAN edge, Docker socket, MQTT auth).

---

## Phase 6 — Observability alignment

**Status:** Open.

**Direction**

- After changing health/rest behavior, update **`monitoring/hosts/pi4-victron/README.md`** targets and alert rules if Prometheus scrapes node-exporter or blackbox on the Pi.
- Prefer **one** restart path so logs/metrics explain failures (avoid systemd restart fighting Compose restart).

**Acceptance:** Monitoring README matches deployed timers/services.

---

## Phase 7 — Production readiness: dependency currency + HA 2026.4 compatibility

**Status:** Implemented on `.105` 2026-06-09 (7.1–7.4 code/docs/tests done; local
ruff + pytest green). **Remaining: operator redeploy on the Pi** — see the
"Operator deployment note" at the end of this phase. Originally added 2026-06-09
after an official-docs research pass (versions verified against PyPI / GitHub
releases / Home Assistant core PRs on that date).

### 7.1 — CRITICAL: Home Assistant Core 2026.4 removed MQTT `object_id`

**Status: Resolved (verified compatible) — 2026-06-09.** Source inspection of
`ha_services` (grep of the locked 2.12.0 wheel and the 2.15.2 / main source on
GitHub) shows the library **never emitted `object_id`** in any discovery payload —
config payloads carry `unique_id`, `name`, `device`, topics, etc., and entity IDs
are auto-generated by HA (registry-stable via `unique_id`). The HA 2026.4 removal
therefore does **not** break this bridge, and no `default_entity_id` migration is
needed (no ha-services release emits it either — nothing in its history mentions
the key). Locked in by regression test
`tests/test_discovery_payload.py` (asserts no removed `object_id`/`obj_id` key in
both the config dict and the exact JSON wire payload). `ha-services` upgraded
2.12.0 → **2.15.2** for currency: 2.15.3/2.15.4 require **Python ≥3.12** while the
image (`python:3.11-bookworm`) and CI run 3.11, so 2.15.2 is the newest compatible
release. The on-Pi `mosquitto_sub -t 'homeassistant/#'` payload capture remains an
operator verification step after redeploy.

- HA deprecated the MQTT discovery option **`object_id`** in favor of
  **`default_entity_id`** (must be **fully qualified**, e.g.
  `sensor.victron_battery_voltage`) — deprecation
  [home-assistant/core#151775](https://github.com/home-assistant/core/pull/151775),
  removal after 6 months in
  [home-assistant/core#164460](https://github.com/home-assistant/core/pull/164460)
  (**HA Core 2026.4**, now shipped).
- This bridge publishes discovery via **`ha_services`** (locked at **2.12.0**,
  released before the deprecation; latest on PyPI is **2.15.4**). Discovery payload
  shape is therefore owned by the library, not this repo.
- **Action:**
  1. Capture a live discovery payload (`mosquitto_sub -t 'homeassistant/#'`) and
     check for `object_id`/`obj_id` keys.
  2. Upgrade `ha-services` in `requirements.lock` to a release that emits
     `default_entity_id` (verify in its changelog), re-sync hub wheels
     (`scripts/sync-victron-wheels-from-hub.sh`), rebuild, and re-verify the payload.
  3. Note the migration caveat from HA: with a `unique_id`, `default_entity_id` is
     only honored on **first** discovery — existing entity IDs in the HA registry
     are preserved, so expect no renames for already-discovered entities.
- **Risk if skipped:** once the Pi's `homeassistant` container (image not pinned to
  a pre-2026.4 tag) updates, newly discovered entities fall back to
  auto-generated/unnamed IDs and dashboards/automations referencing them break.

### 7.2 — Dependency currency (lock vs PyPI, 2026-06-09)

**Status: Done — 2026-06-09.** New pins in `requirements.lock`:

| Package | Was | Now | Notes |
|---|---|---|---|
| `victron-ble` | 0.9.2 | **0.9.3** | Breaking detail found during the bump: `BaseScanner.callback()` gained a third `advertisement: AdvertisementData` argument. Call sites in `override/victron_ble2mqtt/__main__.py`, `override/victron_ble2mqtt/cli_app/mqtt.py`, and `victron_ble2mqtt/test_helpers.py` migrated; RSSI now read from `advertisement.rssi` (the old `_detection_callback` RSSI cache was removed). |
| `bleak` | 1.1.0 | **3.0.2** | `adapter=` kwarg deprecated in 3.0 → migrated to `bluez={"adapter": ...}` ([CHANGELOG v3.0.0](https://github.com/hbldh/bleak/blob/develop/CHANGELOG.rst)). bleak 3.0.2 requires Python ≥3.10 — fine on the 3.11 image. victron-ble pins only `bleak>=0.19.0`, no cap. We only scan (no GATT), so `BleakGATTProtocolError` changes don't apply. |
| `paho-mqtt` | 2.1.0 | 2.1.0 | Already current; `CallbackAPIVersion.VERSION2` in use. |
| `ha-services` | 2.12.0 | **2.15.2** | Newest release supporting Python 3.11 (2.15.3/2.15.4 require ≥3.12 — bumping the base image to 3.12 would force a cp312 hub-wheel re-seed and was deferred). See 7.1. |
| `psutil` | 7.1.3 (`>=7.0,<7.2`) | **7.2.2 (`>=7.2,<8`)** | Pin **flipped**: ha-services 2.15.2 imports `snetio` from `psutil._ntuples`, which only exists in psutil ≥7.2. The old `<7.2` bound was for 2.12.0's `psutil._common` import and now breaks startup. |
| `rich` / `tyro` | 14.1.0 / 0.9.28 | unchanged | Current enough; no API issues. |

Transitive deps move too (e.g. `dbus-fast` 4.0.4 → 5.x for bleak 3): **hub wheels
must be re-seeded** before an offline (`PIP_OFFLINE=1`) build — see operator note.

### 7.3 — Requirements drift (single source of truth)

**Status: Done — 2026-06-09.** `hbmqtt` (abandoned, no Python ≥3.10 support) and
`pytest` removed from `requirements.txt`; the file now lists only direct runtime
deps with ranges matching `requirements.lock` (the single installable source used
by the Dockerfile and CI). Dev tools stay in `[dependency-groups] dev`
(`pyproject.toml`, PEP 735). Original finding:

`requirements.txt` and `requirements.lock` disagree:

- **`hbmqtt`** is listed in `requirements.txt` ("local MQTT broker for testing") but
  not in the lock. hbmqtt is **abandoned** (no release since 2019, incompatible with
  Python ≥3.10 — its PyPI page points to the `amqtt` fork). Remove it; tests already
  run against Mosquitto/paho.
- **`pytest`** sits in runtime `requirements.txt` but belongs only in the
  `[dependency-groups] dev` table of `pyproject.toml` (PEP 735), where it already is.
- **Action:** make `requirements.lock` the single installable source (it already is
  for the Dockerfile); reduce `requirements.txt` to direct runtime deps that match
  the lock, or delete it in favor of `pyproject.toml` + lock. No silent divergence.

### 7.4 — Healthcheck quality (root-cause liveness, not import smoke)

**Status: Done — 2026-06-09.** The publish loop
(`override/victron_ble2mqtt/__main__.py`) now touches a heartbeat file
(`HEARTBEAT_FILE`, default `/tmp/victron_ble2mqtt.heartbeat`) after each
successful system-info publish **while the MQTT client is connected**. The
Dockerfile `HEALTHCHECK` and the Compose `healthcheck` fail when the heartbeat is
older than `20 × SYSTEM_POLL_THROTTLE_SEC + 60s` (default poll 3s → 120s budget;
`start_period` raised to 60s). A wedged asyncio loop or dead MQTT connection now
flips the container `unhealthy`, which autoheal (Phase 1) restarts. Original
finding:

Current Compose/Docker healthcheck only does `import victron_ble2mqtt` — it proves
the interpreter starts, **not** that BLE scanning or MQTT publishing is alive (the
failure modes autoheal exists to fix). Replace with a real liveness probe: e.g. the
publish loop touches a heartbeat file (or exposes last-publish timestamp) and the
healthcheck fails when the last successful publish is older than N×
`SYSTEM_POLL_THROTTLE_SEC`. Compose healthcheck semantics:
[Compose file reference — healthcheck](https://docs.docker.com/reference/compose-file/services/#healthcheck).

### 7.5 — Pin the Home Assistant container image

`docker-compose.homeassistant.yml` + Watchtower control HA updates on the Pi. Pin
HA to an explicit monthly tag and bump deliberately (coordinated with 7.1), instead
of floating — same rationale as the workspace-wide "no `latest` in production"
standard. Verify Watchtower labels gate HA out of auto-upgrade until 7.1 lands.

### Operator deployment note (Pi) — Phase 7 rollout

Since 7.1 turned out to be a non-breakage (ha-services never emitted `object_id`),
there is **no hard deadline**, but keep this order to stay safe:

1. **Before pulling this change:** pin the Pi's `homeassistant` container image to
   the currently running tag in `docker-compose.homeassistant.yml` (e.g.
   `ghcr.io/home-assistant/home-assistant:2026.3`) and confirm Watchtower labels
   keep HA out of auto-upgrade (7.5). This freezes a known-good pairing while the
   bridge image rebuilds.
2. `git pull` this repo on the Pi.
3. Re-seed hub wheels for the new pins (bleak 3.0.2, victron-ble 0.9.3,
   ha-services 2.15.2, psutil 7.2.2 + new transitives such as `dbus-fast` 5.x) on
   `.111`, then `bash scripts/sync-victron-wheels-from-hub.sh` — or build once
   with `PIP_OFFLINE=0` to pull from PyPI.
4. Rebuild + restart: `docker compose -f docker-compose.victron.yml build` and
   `up -d`. Watch `docker inspect victron_ble2mqtt` health flip to `healthy`
   (new heartbeat-based probe; allow the 60s start period).
5. Verify discovery payloads live: `mosquitto_sub -t 'homeassistant/#' -C 5 -v`
   — confirm config payloads contain `unique_id` and **no** `object_id`.
6. Only then update the HA image tag to a ≥2026.4 monthly tag and redeploy HA.
   Existing entity IDs are preserved by the HA registry (`unique_id` match), so
   no dashboard/automation renames are expected.

---

## Suggested implementation order

| Order | Phase | Rationale |
|-------|--------|-----------|
| 1 | 0 | Avoid rework from undocumented assumptions |
| 1 | 4 (minimal) | CI catches regressions while refactoring deploy |
| 2 | 1 | Biggest operational simplification; removes duplicate HA probes |
| 3 | 2 | Makes Phase 1 changes reviewable |
| 4 | 3 | Code quality debt paid incrementally |
| 5 | **7.1 + 7.5** | **Was flagged as production blocker; resolved 2026-06-09 — ha-services never emitted `object_id`, regression test added (see 7.1)** |
| 6 | 7.2–7.4 | Dependency currency, requirements single-source, real liveness probe — done 2026-06-09 |
| 7 | 5–6 | Security narrative + fleet observability |

---

## Rollback / flags

- **`ENABLE_HA_WATCHDOG=1`** — restore legacy timer during transition.
- **`ENABLE_MQTT_WATCHDOG=0`** — only after systemd/Compose Mosquitto story is validated.
- **`ENABLE_TOOLS=0`** — disable Watchtower/autoheal stack slices independently per operator preference.

---

## Related repo docs

- `DEPLOY.md` — installer flags and behavior
- `docs/ALFA_CLUSTER_INTEGRATION.md` — hub wheels / NFS / Prometheus touchpoints
- `AGENTS.md` — Cursor/agent scope for this repo
