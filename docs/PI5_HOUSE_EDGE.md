# Pi 5 house edge — DNS + BLE into Pi 4 Home Assistant

The **Pi 4** runs this repo as `HOST_ROLE=pi4`: Victron, Mosquitto, Home Assistant.
It sits in another building, so its Bluetooth radio cannot hear devices in the house.

The **Pi 5** clones the **same** repo as `HOST_ROLE=pi5`. It is the house radio and
LAN DNS box. It does not run a second Home Assistant.

```
House BLE  ──► Theengs on Pi 5 ──► Mosquitto on Pi 4 :1883 ──► Home Assistant
LAN DNS    ──► AdGuard on Pi 5 (:53 / :8080)
Wi-Fi HVAC ──► HomeKit Device / EcoNet on Pi 4 HA (not BLE, not AdGuard)
```

Installer: `sudo bash scripts/deploy.sh` on each Pi (role from `.env` or LAN IP).
Compose files: [hosts/pi5/](../hosts/pi5/). Operator notes: [hosts/pi5/README.md](../hosts/pi5/README.md).

Prometheus scrape config for `:9100` / `:9617` stays in the **monitoring** repo
on `192.168.0.107`.
