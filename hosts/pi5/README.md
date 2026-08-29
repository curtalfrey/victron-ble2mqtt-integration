# Raspberry Pi 5 — house edge (AdGuard + BLE gateway)

This host (`192.168.0.240` in the homelab) lives **in the house**. The Pi 4
(`192.168.0.223`) runs Home Assistant and Mosquitto in another building, so it
cannot hear house Bluetooth.

Same git repo as the Pi 4. Set **`HOST_ROLE=pi5`** in `.env` (or let deploy
auto-detect this LAN IP) and run:

```bash
sudo bash scripts/deploy.sh
```

That starts:

| Job | What it does |
|-----|----------------|
| **AdGuard Home** | LAN DNS (`:53`) + UI (`:8080`) so you can see which devices query which domains |
| **adguard-exporter** | Prometheus `:9617` (needs `hosts/pi5/adguard-exporter.password`) |
| **node_exporter** | Host metrics `:9100` |
| **Theengs Gateway** | House **BLE** → MQTT on the Pi 4 (`home/TheengsGateway-pi5/BTtoMQTT`) |

It does **not** run Home Assistant, Mosquitto, or Victron. It is **not** a
router: the AXE300 stays DHCP/NAT. Wi-Fi thermostats (Ecobee, Rheem) already
talk IP to HA; add **HomeKit Device** / **EcoNet** on the Pi 4, not here.

## First-time `.env` on this Pi

```bash
cp dotenv.sample .env && chmod 600 .env
```

```text
HOST_ROLE=pi5
MQTT_HOST=192.168.0.223
MQTT_PORT=1883
MQTT_USER=victron
MQTT_PASSWORD=<same as Pi 4 Mosquitto>
```

`MQTT_HOST` must be the **Pi 4** address. `127.0.0.1` here is this Pi, not the broker.

If AdGuard and Theengs were started earlier from the **monitoring** repo
(`~/monitoring/hosts/pi5-dns/`), deploy copies `mqtt.env` and
`adguard-exporter.password` from that folder when they are missing here.

## MQTT file for Theengs

`hosts/pi5/mqtt.env` is gitignored. Deploy writes it from `.env`, or you can
generate it on the Pi 4 and copy it over:

```bash
# on the Pi 4
sudo bash scripts/write_pi5_mqtt_env.sh /tmp/pi5-theengs-mqtt.env
```

## Prometheus

Scrape jobs stay in the **monitoring** repo (`prometheus.yml` on `.107`):
`node-remote` `.240:9100`, `adguard-remote` `.240:9617`.
