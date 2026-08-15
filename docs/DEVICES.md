# Devices — add, skip, or remove

This is the **only page** you need to turn gear on or off.

After any change, on the Pi:

```bash
cd ~/victron-ble2mqtt-integration
sudo bash scripts/deploy.sh
```

Secrets stay in `.env` and `victron-secrets.env` (never commit those files).

---

## Catalog

| Device | How it connects | Default | Turn **on** | Turn **off** / remove |
|--------|-----------------|---------|-------------|------------------------|
| **Victron** SmartShunt / MPPT | Bluetooth (BLE) | On, if you set keys | Add MAC + `ADVKEY_*` | Delete that device block and its `ADVKEY_*` line |
| **Pi4 host** (CPU, temp, Wi‑Fi) | Built into the Victron container | On with Victron | Nothing extra | Stop `victron_ble2mqtt` (you also lose Victron) |
| **Sungold SPH302480A** | USB Modbus (read-only) | **Off** | `ENABLE_SUNGOLD=1` + USB | `ENABLE_SUNGOLD=0` or unplug USB |
| **Home Assistant** | Browser `:8123` | On | `ENABLE_HOME_ASSISTANT=1` (default) | `ENABLE_HOME_ASSISTANT=0` |
| **Refoss / Govee / other HA gear** | Home Assistant integrations | Not this repo | HA → Settings → Devices & services | Remove the integration in HA |

Victron and Sungold both publish into the **same** Mosquitto broker. They do not replace each other.

```
Victron BLE  ──► victron_ble2mqtt ──┐
Sungold USB  ──► sungold_modbus_ro ─┼──► Mosquitto :1883 ──► Home Assistant
Pi4 metrics  ──► victron_ble2mqtt ──┘
```

---

## Victron (Bluetooth)

You need **two** things per device:

1. **MAC address** (Bluetooth ID), e.g. `d4:ef:fb:b3:d7:0c`
2. **Advertisement key** (32 hex characters) from the VictronConnect app

### Find the MAC

Close VictronConnect on your phone, then on the Pi:

```bash
sudo bluetoothctl scan on
```

Wait 20 seconds. Note the address next to your SmartShunt / MPPT. `Ctrl+C` to stop.

### Add a device

1. Edit `override/victron_ble2mqtt/user_settings_data.py`.
2. Add a block to the `devices` list (this repo’s MACs are **examples** — use yours):

```python
    {
        "mac": "aa:bb:cc:dd:ee:ff",
        "type": "SmartShunt",   # or "BlueSolar" for an MPPT
        "name": "Battery 3",
    },
```

3. Edit `victron-secrets.env` and add a key. The name becomes `ADVKEY_` + the name in `SCREAMING_SNAKE`:

```text
ADVKEY_BATTERY_3=0123456789abcdef0123456789abcdef
```

`Battery 1` → `ADVKEY_BATTERY_1`  
`Solar-controller` → `ADVKEY_SOLAR_CONTROLLER`

4. Re-run `sudo bash scripts/deploy.sh`.

### Remove a device

1. Delete that block from `user_settings_data.py`.
2. Delete its `ADVKEY_*` line from `victron-secrets.env`.
3. Re-run deploy.

You do not need to wipe Home Assistant. Old MQTT entities may linger until you remove them under **Settings → Devices & services → MQTT**.

### Victron still missing in HA?

- Close the VictronConnect app.
- Confirm `sudo bluetoothctl show` says **Powered: yes**.
- Weak built-in radio: plug a USB Bluetooth dongle, set `BLE_ADAPTER=hci1` in `.env`, redeploy.

---

## Sungold inverter

**Read-only.** This sidecar never writes settings to the inverter. Change settings on the front panel.

Full hardware notes: [SUNGOLD_SPH302480A.md](SUNGOLD_SPH302480A.md).

### Turn on

1. USB-B cable from the inverter to the Pi.
2. Confirm the stick is seen:

```bash
lsusb | grep -i '1a86\|ch340'
```

3. In `.env`:

```text
ENABLE_SUNGOLD=1
SUNGOLD_SERIAL_DEVICE=/dev/sungold
```

4. `sudo bash scripts/deploy.sh`  
   Deploy installs the udev rule that creates `/dev/sungold`.
5. Check: `bash scripts/sungold_smoke.sh` and `docker logs -f sungold_modbus_ro`.

### Turn off

In `.env`:

```text
ENABLE_SUNGOLD=0
```

Then `sudo bash scripts/deploy.sh`. Victron and Home Assistant keep running.

---

## Home Assistant–only devices (Refoss, Govee, …)

Add these in the Home Assistant UI, not in this git repo:

**Settings → Devices & services → Add integration**

They do not need `ENABLE_*` flags here. Removing them is also done in that same HA screen.

Home Assistant must be connected to MQTT for **Victron / Sungold / Pi4** sensors. The installer does that for you (HA 2026+). Do not paste broker settings into `configuration.yaml`.

---

## Home Assistant itself

| Flag in `.env` | Result |
|----------------|--------|
| `ENABLE_HOME_ASSISTANT=1` (default) | Dashboard at `http://PI-IP:8123` |
| `ENABLE_HOME_ASSISTANT=0` | No HA container (MQTT + Victron still run) |

---

## Checklist for a YouTube / new-user setup

Copy this and tick as you go:

- [ ] Pi on the network; `hostname -I` written down
- [ ] `git clone` + `cp dotenv.sample .env`
- [ ] `MQTT_HOST` / `MQTT_USER` / `MQTT_PASSWORD` set
- [ ] Victron: MACs in `user_settings_data.py`, keys in `victron-secrets.env`
- [ ] `sudo bash scripts/deploy.sh` finished; `docker ps` shows `victron_ble2mqtt` and `homeassistant`
- [ ] Browser: `http://PI-IP:8123` — account created
- [ ] MQTT devices visible in HA
- [ ] Sungold only if USB is plugged: `ENABLE_SUNGOLD=1`

---

## Adding a *new kind* of device to this repo (developers)

If you are building another sidecar (not just another Victron MAC):

1. Add a row to the **Catalog** table above.
2. Default it **off** (`ENABLE_YOURDEVICE=0` in `dotenv.sample`).
3. Gate it in `scripts/deploy.sh` the same way as Sungold.
4. Link a short `docs/YOURDEVICE.md` from this page and from the README table.
5. Do not change Victron BLE or write to inverters unless the operator asks.

Beginners should not need that path. Use the catalog switches.
