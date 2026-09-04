# Pi 5 house edge — DNS + BLE into `.105` Home Assistant

Mosquitto and Home Assistant run on **`.105` (`192.168.0.105`)**. The **Pi 4**
(`HOST_ROLE=pi4`) is the Victron BLE / Sungold USB radio in another building.
The **Pi 5** (`HOST_ROLE=pi5`) is the house radio and LAN DNS box. It does not
run a second Home Assistant.

```
House BLE  ──► Theengs on Pi 5 ──► Mosquitto on .105 :1883 ──► HA Container
Solar-site BLE (Govee, …) ──► Theengs on Pi 4 ──► same broker
LAN DNS    ──► AdGuard on Pi 5 (:53 / :8080)
Victron    ──► victron_ble2mqtt on Pi 4 ──► same broker
```

Pi4 also runs **Theengs** (`hosts/pi4/docker-compose.theengs.yml`) so BLE next to
the Victron gear (the H5075 at `A4:C1:38:CA:AF:6F`) is heard there. Do **not**
run `scripts/deploy.sh` on Pi4 to add Theengs — that installer still starts HA
and Mosquitto. Load `theengs/gateway:v1.7.5.1` from the hub tarball
`theengs-gateway-v1.7.5.1.tar.gz`, write `hosts/pi4/mqtt.env` with
`scripts/write_theengs_mqtt_env.py`, then:

```bash
cd ~/victron-ble2mqtt-integration/hosts/pi4
sudo docker compose -f docker-compose.theengs.yml up -d
```

Installer: `sudo bash scripts/deploy.sh` on each Pi (role from `.env` or LAN IP).
Compose files: [hosts/pi5/](../hosts/pi5/). Operator notes: [hosts/pi5/README.md](../hosts/pi5/README.md).

Prometheus scrape config for `:9100` / `:9617` stays in the **monitoring** repo
on `192.168.0.107`.
