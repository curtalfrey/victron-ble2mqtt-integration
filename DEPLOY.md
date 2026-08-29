# Deploy (operator reference)

**First time, or sharing this on YouTube?** Start at the **[README](README.md)** (copy-paste install). To turn Victron / Sungold / Home Assistant on or off, use **[docs/DEVICES.md](docs/DEVICES.md)**. Two Pis from one clone: **`HOST_ROLE=pi4`** (this stack) vs **`HOST_ROLE=pi5`** (house AdGuard + BLE gateway) — [docs/PI5_HOUSE_EDGE.md](docs/PI5_HOUSE_EDGE.md). To view Home Assistant away from home, use **[docs/TAILSCALE.md](docs/TAILSCALE.md)** (do not publish LAN IPs or Tailscale names). This page is the longer installer reference.

---

Quick deploy (recommended)

Preconditions (on the host):
- Debian/Raspberry Pi OS host with sudo
- Network access and Bluetooth enabled (BlueZ)
- Optional: `.env` with MQTT creds and ADVKEY_* (script will prompt/create placeholders if missing)

What the installer does (idempotent):
- Installs Docker Engine + Compose plugin if missing and enables the service
- Configures safe Docker logging defaults globally (json-file with rotation 10MB x3), then merges **`registry-mirrors`** (`http://192.168.0.111:5000` by default) so Docker Hub pulls route through the TrueNAS mirror when on the Alfa LAN
   - If `/etc/docker/daemon.json` is malformed, it will be backed up, rewritten with valid JSON, and Docker will be restarted
   - Disable mirror injection with **`ENABLE_DOCKER_REGISTRY_MIRROR=0`** (off‑LAN Pi / no `.111`)
- Sets journald caps (disk/RAM) and logrotate for app/HA logs
- Installs Mosquitto (broker + clients) and configures auth if MQTT_USER/MQTT_PASSWORD are set
- Builds the app image (`victron_ble2mqtt:local`) with **`PIP_OFFLINE=1`** when **`./wheels`** contains `.whl` files synced from **`/mnt/cluster/wheels/victron`** (see **`docs/ALFA_CLUSTER_INTEGRATION.md`**); otherwise pip resolves from PyPI
- Removes legacy systemd runners (`victron-ble2mqtt.service`, `victron-tools.service`) if present
- Installs **Dockge** under **`/opt/dockge`** (host UI **`http://<pi-ip>:5006`**) and writes **`/opt/stacks/<stack>/compose.yaml`** wrappers that `include` the repo Compose files (paths in those files resolve to the repo root)
- Starts **`victron`**, **`homeassistant`**, **`autoheal`** ([willfarrell/autoheal](https://hub.docker.com/r/willfarrell/autoheal)), and optionally **`tools`** (Watchtower only) via Compose — workloads use **`restart: unless-stopped`**; **`healthcheck`** + **`autoheal`** restart **wedged** containers labeled **`autoheal=true`**
- Starts optional helper timers (docker prune, MQTT watchdog, VS Code cleanup). Legacy systemd **`ha-watchdog.timer`** is **off** by default (`ENABLE_HA_WATCHDOG=0`); use **`ENABLE_HA_WATCHDOG=1`** only if you deliberately want duplicate HTTP probes alongside Compose.

Steps (copy/paste):

### Fresh Raspberry Pi OS (optional one-shot)

Bootstrap helper lives in the **alfa-ai** sibling repo (not this tree):

```bash
# From a machine that has alfa-ai checked out (or copy the script onto the Pi):
bash /path/to/alfa-ai/scripts/bootstrap_pi4_victron_ble2mqtt_integration.sh
```

Or clone this repo and run deploy directly (below).

1) Clone the repo and create `.env` for MQTT (and optional Wi-Fi / tools)

   git clone https://github.com/Curt-Alfrey-s-Org/victron-ble2mqtt-integration.git
   cd victron-ble2mqtt-integration
   cp -n dotenv.sample .env && chmod 600 .env   # then edit: MQTT_USER, MQTT_PASSWORD
   # ADVKEY_* may live in .env **or** ./victron-secrets.env — if both set the same
   # variable, **.env wins** (see scripts/redeploy_victron.sh). Prefer victron-secrets.env
   # for keys only (chmod 600); deploy creates empty placeholders there on first run.
   # Or run deploy once — it creates/appends MQTT_* lines if `.env` is missing or has no MQTT_USER=.
   cp config/user_settings.example.py user_settings.local.py # optional

2) Build and run (unified installer)

   sudo bash scripts/deploy.sh

   # Optional features via env flags (set before running):
   # ENABLE_PERF_TUNING=1     # apply systemd+udev performance tweaks
   # ENABLE_DOCKGE=1          # install Dockge + /opt/stacks wrappers (default on)
   # ENABLE_TOOLS=1           # deploy Watchtower stack (docker-compose.tools.yml, default on)
   # ENABLE_AUTOHEAL=0        # skip docker-compose.autoheal.yml (default 1 — recommended)
   # ENABLE_HA_WATCHDOG=1     # legacy systemd HTTP probe + docker restart (default 0)
   # ENABLE_FAILOVER_MONITOR=1# enable Wi-Fi failover monitor@user service
   # ENABLE_DOCKER_REGISTRY_MIRROR=0 # skip LAN registry mirror (default 1)
   # DOCKER_REGISTRY_MIRROR=http://192.168.0.111:5000  # override mirror URL
   # ENABLE_HOME_ASSISTANT=0       # skip Home Assistant compose (no GHCR) until hub tarball exists
   # HOST_ROLE=pi5              # house Pi: AdGuard + Theengs (skips Victron/HA/Mosquitto)
   # TRUENAS_IP=192.168.0.111   # TrueNAS address for ping + mount-truenas-hub.sh
   # HA_IMAGE=ghcr.io/home-assistant/home-assistant:2026.7.3  # Compose pin (default)
   # HA_IMAGE_TARBALL=/path/to/home-assistant-2026.7.3.tar.gz  # optional explicit docker load

   docker ps --filter name=victron_ble2mqtt
   docker logs -f victron_ble2mqtt
   curl -fsSI "http://127.0.0.1:5006/"   # Dockge UI (or open http://<pi-lan-ip>:5006 from LAN)

   If `docker ps` as your normal user says **permission denied**, deploy already added you to the **docker** group — **log out and back in** (or `newgrp docker`) so the socket is usable interactively.

Notes:
- **Sources of truth:** Application Compose files live in this repo (`docker-compose.*.yml`). Dockge wrappers under **`/opt/stacks/<stack>/compose.yaml`** only **`include`** those paths. Mosquitto is a **host `systemd` service** (`mosquitto.service`) with config under **`/etc/mosquitto`** (written by `deploy.sh`). Secrets: **`.env`** and **`victron-secrets.env`** (chmod 600); MQTT watchdog client credentials: **`/etc/mosquitto/watchdog.env`** (written by deploy when Mosquitto auth is enabled).
- **Dockge:** Stacks appear under **`/opt/stacks`** (`victron`, `homeassistant`, `autoheal`, `tools`, and **`sungold`** when `ENABLE_SUNGOLD=1`). Compose **`include`** points at files in your git checkout — edit Compose in the repo, then **Compose → Update** in Dockge or re-run **`sudo bash scripts/deploy.sh`** to refresh wrappers.
- **Sungold SPH302480A (optional):** Read-only USB Modbus sidecar — **`docs/SUNGOLD_SPH302480A.md`**. Default off (`ENABLE_SUNGOLD=0`). Does not change Victron BLE.
- **Mosquitto broker:** `deploy.sh` runs `mosquitto_restart_and_verify()` after writing config. It checks that the service is active, a listener exists on the port, and `mosquitto_sub` succeeds (with credentials when auth is enabled). The MQTT watchdog timer sources `/etc/mosquitto/watchdog.env`.
- **MQTT_HOST recommendation:** Set `MQTT_HOST` in `.env` to the Pi's **LAN IP** (e.g. `192.168.0.50`). `redeploy_victron.sh` will use it instead of `localhost` if `localhost` or `127.0.0.1` is detected. This avoids connection refused when the container tries to connect.
- **Home Assistant → MQTT (HA 2026+):** Broker settings in `configuration.yaml` / `mqtt.yaml` are **invalid**. `deploy.sh` runs `scripts/ha_enable_mqtt_integration.sh` after HA starts (config entry → `127.0.0.1:1883`, same `.env` Mosquitto creds). Do not use `FORCE_HA_MQTT_YAML=1` or the old YAML writers. Preflight: `set -a; . ./.env; set +a` then `mosquitto_sub -h "${MQTT_HOST:-127.0.0.1}" -p 1883 -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t '$SYS/broker/uptime' -C 1 -W 8 -v`. If it fails, run `journalctl -u mosquitto -n 60`.
- **Home Assistant compose:** `docker-compose.homeassistant.yml` uses `env_file: ./ha-discovery.env`. If that file is missing, **`deploy.sh`** creates it from **`swarm/ha-discovery.env`** (if present) or **`swarm/ha-discovery.env.example`**, or writes a minimal stub from current **`MQTT_*`** env.
- Uses host networking for Bluetooth and MQTT (see `docker-compose.victron.yml`).
- If you prefer prebuilt images, push to GHCR and adjust compose to pull.
- Logging/operations hardening included:
   - Docker daemon log rotation (10MB x3) via `/etc/docker/daemon.json` (auto-repaired if broken)
   - journald caps and logrotate for app/HA logs
   - Mosquitto logs routed to syslog with reduced verbosity
- Optional automation: legacy HA systemd watchdog (`ENABLE_HA_WATCHDOG=1`), MQTT watchdog, weekly docker prune, VS Code cleanup timer.

**Verify autoheal (on the Pi):** `docker inspect homeassistant --format '{{json .State.Health}}'` — after intentional stall, container should return **`healthy`** following an **`autoheal`** restart (`docker logs autoheal`).

**TrueNAS hub (same LAN as Alfa):** **`deploy.sh`** tries **`scripts/mount-truenas-hub.sh`** when **`ENSURE_TRUENAS_NFS_MOUNT=1`** (default) and TrueNAS **`TRUENAS_IP`** (default **`192.168.0.111`**) pings but **`wheels/victron`** is empty locally — same NFS layout as **`alfa-ai/scripts/mount_nfs_models.sh`**. Seed wheels on `.111` with **`alfa-ai/scripts/seed-victron-wheels-truenas.sh`** so **`sync-victron-wheels-from-hub`** can fill **`./wheels`** and set **`PIP_OFFLINE=1`**. Seed the HA image: on `.111` `docker pull ghcr.io/home-assistant/home-assistant:2026.7.3` then **`publish-built-image-to-hub.sh`** → **`home-assistant-2026.7.3.tar.gz`** (legacy **`home-assistant-stable.tar.gz`** still loads and is retagged). Otherwise Compose may pull **GHCR** (~1.5 GB). Disable auto-mount with **`ENSURE_TRUENAS_NFS_MOUNT=0`** if the Pi is off-LAN.

**Home Assistant pin:** `docker-compose.homeassistant.yml` uses a monthly tag (default **`2026.7.3`**), not `:stable`. Watchtower is label-gated and does **not** auto-upgrade HA. Bump `HA_IMAGE` deliberately after reading [HA container release notes](https://www.home-assistant.io/common-tasks/container/).

**Legacy guides:** `Victron_BLE_to_MQTT_Integration_Setup_Guide.md` / `Victron_Ble2mqtt_Install.md` describe the old venv/systemd path — prefer this file + Docker Compose for new installs.
- Docker won’t start after running the installer: check `/etc/docker/daemon.json`. The installer backs up invalid files and writes valid JSON, then restarts Docker.
- **`victron_ble2mqtt` exits / BLE issues:** verify `bluetoothctl show` reports `Powered: yes`; run **`sudo bash scripts/deploy.sh`** or **`docker restart victron_ble2mqtt`**. Legacy **`victron-ble2mqtt.service`** is removed by deploy — do not re-enable it.
- No HA entities after discovery: ensure the Victron app is closed (it can stop adverts), and verify ADVKEY_* values are correct.
- USB BLE dongle: add `BLE_ADAPTER=hci1` (or whatever `bluetoothctl list` shows) to `.env`, then `sudo bash scripts/redeploy_victron.sh` — the bridge defaults to BlueZ’s default adapter (`hci0`) unless overridden.

Network failover (eth0 -> wlan0):
- Ensure Wi‑Fi credentials are present in `.env` as WIFI_SSID/WIFI_PASSWORD or saved in NetworkManager.
- The deploy script prefers Ethernet and falls back to Wi‑Fi automatically via route metrics.
- Optional watchdog to keep Wi‑Fi up when Ethernet drops:
   1. Install unit: `sudo install -m 644 systemd/wifi-failover-monitor@.service /etc/systemd/system/wifi-failover-monitor@.service`
   2. Reload: `sudo systemctl daemon-reload`
   3. Enable: `sudo systemctl enable --now wifi-failover-monitor@<user>.service`
   4. Logs: `journalctl -u wifi-failover-monitor@<user>.service -f`
