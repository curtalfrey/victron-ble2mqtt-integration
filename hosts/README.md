# Host roles (one repo, two Raspberry Pis)

`scripts/deploy.sh` reads **`HOST_ROLE`** from `.env` (or guesses from the LAN IP).

| `HOST_ROLE` | Typical IP | What `deploy.sh` starts |
|-------------|------------|-------------------------|
| **pi4** (default) | `192.168.0.223` | Mosquitto, Victron BLE, Home Assistant, optional Sungold |
| **pi5** | `192.168.0.240` | AdGuard DNS, Theengs house BLE → Pi 4 MQTT, node_exporter |

Pi 5 details: [hosts/pi5/README.md](pi5/README.md) and [docs/PI5_HOUSE_EDGE.md](../docs/PI5_HOUSE_EDGE.md).
