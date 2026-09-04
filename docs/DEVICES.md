# Devices — add, skip, or remove

This is the **only page** you need to turn gear on or off.

After any change, on **that** Pi (`HOST_ROLE=pi4` or `pi5`):

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
| **House BLE sensors** (Govee, Xiaomi, …) | BLE on **Pi 5** → MQTT on this Pi | Off until Pi 5 deploy | `HOST_ROLE=pi5` on the house Pi | `docker compose … down` on Pi 5 |
| **Ecobee / Rheem / other Wi‑Fi HVAC** | HomeKit Device / EcoNet (LAN), not BLE | Not this repo | HA → Settings → Devices & services | Remove the integration in HA |
| **Refoss / Govee / other HA gear** | Home Assistant integrations | Not this repo | HA → Settings → Devices & services | Remove the integration in HA |
| **Away-from-home view** | Tailscale VPN (optional) | Off (not in deploy) | Install Tailscale on Pi + phone | Uninstall / log out of Tailscale |

Victron and Sungold both publish into the **same** Mosquitto broker. They do not replace each other.

The house Pi 5 (`HOST_ROLE=pi5`) publishes decoded BLE into that same broker. Wi-Fi HVAC does not use Theengs.

```
Victron BLE (Pi 4 radio)               ──► victron_ble2mqtt ──┐
Sungold USB                            ──► sungold_modbus_ro ─┼──► Mosquitto :1883 ──► Home Assistant
Pi4 metrics                            ──► victron_ble2mqtt ──┤
House BLE (Pi 5 radio)                 ──► Theengs Gateway ───┘
```

---

## Victron (Bluetooth)

You need **two** things per device:

1. **MAC address** (Bluetooth ID), e.g. `d4:ef:fb:b3:d7:0c`
2. **Advertisement key** (exactly **32 hex characters**) from VictronConnect
   Instant Readout Details ([keshavdv/victron-ble](https://github.com/keshavdv/victron-ble)).
   Do **not** truncate a longer paste. A 33-character value decrypts as garbage
   (impossible volts/amps/watts). If HA shows Battery 1 at hundreds of volts
   while the MPPT is ~26 V, re-copy the key from the app.

Home Assistant cards for current, voltage, and power use **one decimal**
(`suggested_display_precision: 1` on MQTT discovery — [MQTT sensor](https://www.home-assistant.io/integrations/sensor.mqtt/#suggested_display_precision)).
Energy (Wh) and percent sensors are unchanged.

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

## House BLE (Pi 5 radio → this Mosquitto)

The Pi 4 cannot hear Bluetooth in the house. Clone **this same repo** on the Pi 5,
set `HOST_ROLE=pi5` (or use LAN IP `192.168.0.240`), and run `sudo bash scripts/deploy.sh`.

That starts **Theengs Gateway**, which publishes decoded sensors to **this** broker.
Do **not** run a second Home Assistant on the Pi 5. Do **not** put Victron `ADVKEY_*`
keys on Theengs.

Full notes: [PI5_HOUSE_EDGE.md](PI5_HOUSE_EDGE.md), [hosts/pi5/README.md](../hosts/pi5/README.md).
Topic: `home/TheengsGateway-pi5/BTtoMQTT`.

## Wi‑Fi HVAC (Ecobee, Rheem)

These are **not** Victron-style BLE. Add them on the **existing** Home Assistant on the Pi 4 (`:8123`). Do not add a second HA on the Pi 5.

### Ecobee (local)

Use **HomeKit Device**, not **HomeKit Bridge**, and not **ecobee** (that one is cloud).

1. If the thermostat is in **Apple Home**, remove it there first. HomeKit allows only one controller.
2. On the thermostat: **Menu → Settings → HomeKit → Enable pairing**. The 8-digit code appears on screen (often `XXXX-XXXX`; in HA type `XXX-XX-XXX` or the 8 digits).
3. In HA: **Settings → Devices & services**. If it is not already discovered, **Add integration → HomeKit Device**.
4. Enter the pairing code. You should get a `climate.*` entity plus any Eco sensors.

`configuration.yaml` on this Pi must include `zeroconf:` (or `default_config:`) so mDNS discovery works. HA and the thermostat must be on the same LAN subnet.

Cloud fallback (internet, more features): **Add integration → ecobee** with the ecobee.com email/password. Leave **API key** blank. **HA 2026.6+** is required for that login (MFA / Auth0). 2026.4.x crashes with “Unknown error occurred” (`IndexError` in python-ecobee-api 0.3.2). This stack pins **2026.7.3**. SMS/push MFA is unsupported; use an authenticator app.

### Rheem heat-pump water heater (cloud)

1. Confirm the heater is in the **EcoNet** app and you can log in there.
2. **Settings → Devices & services → Add integration → Rheem EcoNet Products**.
3. Use the **same** EcoNet email and password as the app (password usually needs a special character).

You get a `water_heater.*` entity. EcoNet does **not** report tank temperature. It is cloud (ClearBlade), not BLE.

If add/login fails with “Unknown error” / “invalid login” **after** HA is on **2026.7+**, the container no longer trusts Rheem’s old DigiCert G1 chain. Run `sudo bash scripts/ha_econet_trust_g1.sh`, set `HA_SSL_CERT_FILE=/config/ssl/ca-bundle+g1.pem` in `.env`, and recreate the `homeassistant` container. Official notes: [EcoNet SSL troubleshooting](https://www.home-assistant.io/integrations/econet/#ssl-certificate-verification-failed-home-assistant-container-installs). Do not disable TLS.

## Home Assistant–only devices (Refoss, Govee, …)

Add these in the Home Assistant UI, not in this git repo:

**Settings → Devices & services → Add integration**

They do not need `ENABLE_*` flags here. Removing them is also done in that same HA screen.

Home Assistant must be connected to MQTT for **Victron / Sungold / Pi host / house BLE (Theengs)** sensors. The installer does that for you (HA 2026+). Do not paste broker settings into `configuration.yaml`.

---

## Away from home (Tailscale)

Not a device in this repo. Install Tailscale on the Pi and on your phone to open the **same** Home Assistant dashboard on cellular. Do not put Tailscale keys or machine names in git. Full steps: [TAILSCALE.md](TAILSCALE.md).

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
- [ ] Optional away-from-home: [TAILSCALE.md](TAILSCALE.md) (no keys in git)

---

## Adding a *new kind* of device to this repo (developers)

If you are building another sidecar (not just another Victron MAC):

1. Add a row to the **Catalog** table above.
2. Default it **off** (`ENABLE_YOURDEVICE=0` in `dotenv.sample`).
3. Gate it in `scripts/deploy.sh` the same way as Sungold.
4. Link a short `docs/YOURDEVICE.md` from this page and from the README table.
5. Do not change Victron BLE or write to inverters unless the operator asks.

Beginners should not need that path. Use the catalog switches.
