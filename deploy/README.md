Production deployment notes — Raspberry Pi (aarch64)

**New install?** Use the root [README](../README.md) and [docs/DEVICES.md](../docs/DEVICES.md). This file is extra production detail.

Goal
- **Pi 4:** Run **victron-ble2mqtt**, **Home Assistant**, **Dockge**, and optional **Watchtower**.
- **Pi 5:** Same git checkout with **`HOST_ROLE=pi5`** — AdGuard DNS + Theengs BLE gateway (no second HA). See [docs/PI5_HOUSE_EDGE.md](../docs/PI5_HOUSE_EDGE.md).

Assumptions
- Host is Raspberry Pi OS / Debian-based aarch64 with Docker Engine and Docker Compose v2 installed.
- You have the repository checked out on the Pi at `/home/<user>/victron-ble2mqtt-integration`.
- Required secrets (MQTT credentials, ADVKEY_*) are provided via `.env` / `victron-secrets.env` and not committed to git.

Steps
1) Prepare the host
   - Install Docker and Compose v2 (e.g., from Docker's APT repo).
   - Add your user to the docker group and reboot (or use sudo for docker commands).
2) Build multi-arch images (recommended) on a build machine or use buildx on the Pi.
   - On the Pi (local build):
     docker buildx create --use --name mybuilder || true
     docker buildx build --platform linux/arm64 -t victron_ble2mqtt:pi-aarch64 --load .
   - Or build on an x86 builder and push to a registry with multi-arch manifests:
     docker buildx build --platform linux/amd64,linux/arm64 -t <your-registry>/victron_ble2mqtt:latest --push .
3) Configure secrets
   - Create a `.env` containing MQTT_HOST, MQTT_PORT, MQTT_USER, MQTT_PASSWORD and ADVKEY_* entries.
   - Keep secrets out of repo; use environment-managed secrets in production if possible.
4) Runtime overlays
   - Mount `override/` to `/work/override` (the Compose files already do this).
   - Ensure `override/victron_ble2mqtt/user_settings_data.py` contains only non-secret device metadata.
5) Unified installer (recommended)
   - On the Pi:
     sudo bash scripts/deploy.sh
   - This installs **Dockge** at **`http://<pi-ip>:5006`**, creates **`/opt/stacks/*/compose.yaml`** includes pointing at this repo, removes legacy systemd runners, and brings up **victron**, **homeassistant**, and **Watchtower** (label-gated).
6) Manual Compose (without Dockge)
   - `ENABLE_DOCKGE=0 sudo -E bash scripts/deploy.sh` skips Dockge but still starts stacks from the repo directory.
7) Hardening checklist
   - **Dockge** and Watchtower hold the Docker socket — restrict LAN access (firewall) to **`5006`** and SSH.
   - Rotate MQTT and Dockge credentials; limit exposure of Home Assistant (**8123**) to trusted networks.
   - Enable docker daemon log rotation and limit container logging sizes (compose files set json-file rotation where applicable).
   - Ensure Watchtower labels are set only on containers you want auto-updated (`WATCHTOWER_LABEL_ENABLE=true` is already set).

Troubleshooting
- If BLE/BlueZ access fails, ensure the container has access to `/run/dbus/system_bus_socket` and the dbus mounts in `docker-compose.victron.yml`.

Notes
- The `docker-entrypoint.sh` generates `/work/victron_ble2mqtt/user_settings.py` at container start and reads ADVKEY_* environment variables rather than embedding secrets into the repo.
- For production at scale, prefer registry images and orchestration (docker swarm / k3s) if you need higher availability than a single Pi.
