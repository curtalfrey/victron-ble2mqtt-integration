# Victron BLE to MQTT Integration

This repository provides working examples and templates for integrating Victron Smart devices (e.g., MPPTs, SmartShunts) using [victron-ble2mqtt](https://github.com/Louisvdw/victron-ble2mqtt). These examples allow for forwarding Victron data to your platform of choice such as Home Assistant, Node-RED, or others.

## ⚠️ Compatibility and Scope

* Confirmed working with Victron 75/15 MPPTs, Victron SmartShunt, and Venus OS running on Raspberry Pi.
* Current integrations include:

  * Home Assistant (via MQTT dashboard)
  * Node-RED (via MQTT flow)

## 📁 Dashboard Directory

All dashboard files are located under the `dashboards/` folder.

## 🧩 Dashboard JSON Files

### Home Assistant

* **Path:** `dashboards/home_assistant_mqtt.json`
* **Description:** Imports into Home Assistant's MQTT dashboard to visualize Victron Smart device data.
* 📝 *Comment inside JSON marks where to replace MAC address.*

### Node-RED

* **Path:** `dashboards/nodered_victron_flow.json`
* **Description:** Full Node-RED flow to subscribe to Victron MQTT topics and build your own dashboard or automations.

> Replace MAC addresses or topic filters as needed inside these files. Look for comment markers `# REPLACE_ME`.

## 🔧 Setup

### Step 1: Clone This Repo

```bash
cd ~
git clone https://github.com/curtalfrey/victron-ble2mqtt-integration.git
cd victron-ble2mqtt-integration
```

### Step 2: Edit `user_settings.py`

```bash
nano setup/user_settings.py
```

Make sure to:

* Replace MAC addresses with your actual Victron device MACs
* Modify MQTT settings if needed

### Step 3: Configure `victron_ble2mqtt.service`

```bash
sudo cp setup/victron_ble2mqtt.service /etc/systemd/system/victron_ble2mqtt.service
sudo systemctl daemon-reload
sudo systemctl enable victron_ble2mqtt.service
sudo systemctl start victron_ble2mqtt.service
```

### Step 4: Import Dashboards

* For Home Assistant, use the GUI to import `home_assistant_mqtt.json`
* For Node-RED, open the Node-RED UI and import `nodered_victron_flow.json` via the editor

## ✅ Fix for Common `user_settings.toml` Error

If `user_settings.toml` is not being loaded or is causing errors, skip it completely and use `user_settings.py`. This repo provides a verified working `user_settings.py` that eliminates TOML-related issues.

## 📌 Keywords for Searchability

```
victron-ble2mqtt not working
victron user_settings.toml error
victron_ble2mqtt.service fix
victron ble mqtt node-red
victron mqtt home assistant
```

## 🔐 Notes on Privacy

* All user-specific info like usernames have been scrubbed.
* Replace any placeholders with your actual values before deploying.

---

### Contributions Welcome

Submit a PR if you'd like to share other dashboards (e.g., for Grafana, InfluxDB, etc.)

---

© 2025 Curt Alfrey | [alfaqd.com](https://alfaqd.com)
