# Sungold SPH302480A — read-only Modbus → MQTT → Home Assistant

**Most people:** plug the USB cable, set `ENABLE_SUNGOLD=1` in `.env`, run `sudo bash scripts/deploy.sh`. On/off and how this fits next to Victron: **[DEVICES.md](DEVICES.md#sungold-inverter)**. First install: **[README](../README.md)**.

Sibling sidecar to **victron_ble2mqtt**. Publishes **sensors and binary_sensors only** — no HA controls, no Modbus writes. Change inverter settings on the **front panel** only.

## Hardware

| Item | Value |
|------|--------|
| Model | Sungold **SPH302480A** (SRNE-class hybrid) |
| Link | USB-B → Pi (CH340 serial, vendor **1a86**) |
| Modbus | RTU **9600 8N1**, slave address **1** |
| Phase | Single-phase **120 V**, one MPPT |

## Architecture

```
SPH302480A (USB) → sungold_modbus_ro → Mosquitto (:1883) → Home Assistant
Victron BLE      → victron_ble2mqtt  → Mosquitto (:1883) → Home Assistant
```

- Victron stack is **unchanged**.
- Discovery prefix: `homeassistant/sensor/sungold_sph302480a-*` (and `binary_sensor`).
- MQTT topic root: `MQTT_TOPIC=sungold_sph302480a` (distinct from Victron).

## Operator setup (Pi4)

### 1. Plug USB

Connect the inverter **USB-B** cable to the Pi. Confirm CH340:

```bash
lsusb | grep -i '1a86\|ch340\|qinheng'
ls -l /dev/serial/by-id/
```

Typical by-id path (example — yours may differ):

```text
/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
```

### 2. Udev stable symlink

```bash
sudo cp udev/99-sungold-ch340.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=tty
ls -l /dev/sungold
```

Or re-run **`sudo bash scripts/deploy.sh`** with `ENABLE_SUNGOLD=1` (installs the rule automatically).

### 3. Configure `.env`

Add to `.env` (see `dotenv.sample`):

```bash
ENABLE_SUNGOLD=1
SUNGOLD_SERIAL_DEVICE=/dev/sungold
# Or the full by-id path:
# SUNGOLD_SERIAL_DEVICE=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
MQTT_TOPIC=sungold_sph302480a
DEVICE_NAME=Sungold SPH302480A
MODBUS_ADDRESS=1
POLL_INTERVAL_SEC=5
```

Uses the same **`MQTT_HOST` / `MQTT_USER` / `MQTT_PASSWORD`** as Victron and Home Assistant.

### 4. Deploy

```bash
sudo bash scripts/deploy.sh
# Or stack only:
docker compose -f docker-compose.sungold.yml up -d --build
```

Dockge: stack appears as **`sungold`** under `/opt/stacks/sungold` when `ENABLE_DOCKGE=1`.

### 5. Verify

```bash
bash scripts/sungold_smoke.sh
```

Manual checks:

```bash
docker logs -f sungold_modbus_ro
mosquitto_sub -h "$MQTT_HOST" -p 1883 -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
  -t 'sungold_sph302480a/sensor/+/state' -v
mosquitto_sub -h "$MQTT_HOST" -p 1883 -u "$MQTT_USER" -P "$MQTT_PASSWORD" \
  -t 'homeassistant/sensor/sungold_sph302480a-+/config' -C 3 -W 5
```

In Home Assistant: **Settings → Devices & services → MQTT** — device **Sungold SPH302480A** with PV, battery, grid, load, and temperature entities.

## Published entities (curated)

| Area | Examples |
|------|-----------|
| PV | voltage, current, power |
| Battery | SOC, voltage, current, temperature, charge state |
| Grid | voltage, current, frequency, power |
| Load | current, power |
| Inverter | state, AC voltage/frequency, charging power, fault codes |
| Temperature | DC-DC, DC-AC, transformer |
| Binary | fault active |

Unsupported registers are **skipped** after repeated read failures (logged once); discovery entries are removed until retry.

## Troubleshooting

| Symptom | Action |
|---------|--------|
| Deploy skips Sungold | Set `ENABLE_SUNGOLD=1`; confirm `/dev/sungold` or `SUNGOLD_SERIAL_DEVICE` exists |
| Container unhealthy | No Modbus data yet — check cable, address, baud; `docker logs sungold_modbus_ro` |
| No HA entities | Confirm HA MQTT integration uses same broker; check discovery topics with `mosquitto_sub` |
| Permission denied on serial | User in `dialout` group; udev rule sets `GROUP=dialout` |

## Out of scope

- HA write controls (switch/number/select/button).
- SolarAssistant / Voltronic PI30 path.
- Changes to Victron BLE or ADVKEY configuration.

## Reference

Register map derived from [timbit123/srne-modbus](https://github.com/timbit123/srne-modbus) (Apache-2.0). This repo ships a **thin read-only** subset, not a full upstream clone.
