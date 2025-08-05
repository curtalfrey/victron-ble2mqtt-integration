# Victron BLE2MQTT Integration Toolkit

This repository contains a complete guide and set of integration tools to:

* Run `victron-ble2mqtt` as a systemd service
* Use MQTT data in dashboards (Grafana, Node-RED, or Home Assistant)
* Provide example configs and flows for each target system

---

## 📦 Project Structure

```
victron-ble2mqtt-integration/
├── README.md
├── setup/
│   ├── user_settings.py             # Example BLE device config
│   ├── victron_ble2mqtt.service    # Custom systemd unit file
│   └── victron_ble2mqtt.toml       # Optional TOML-style config
├── dashboards/
│   ├── grafana_example.json        # Grafana dashboard export
│   ├── nodered_flow.json           # Node-RED flow (MQTT->Dashboard)
│   └── home_assistant.yaml         # HA discovery YAML
```

---

## 🧠 What Is This?

This repo documents how to:

* Set up `victron-ble2mqtt` on a Raspberry Pi running [Venus OS](https://github.com/victronenergy/venus/wiki)
* Run it persistently with `systemd`
* Send live BLE data to any MQTT-compatible dashboard

---

## 🚀 Quick Start

### 1. Clone this repo

```bash
git clone https://github.com/curtalfrey/victron-ble2mqtt-integration.git
cd victron-ble2mqtt-integration
```

### 2. Customize your settings

Edit `setup/user_settings.py` to match your BLE MAC addresses.

### 3. Copy the systemd unit file

```bash
sudo cp setup/victron_ble2mqtt.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable victron_ble2mqtt
sudo systemctl start victron_ble2mqtt
```

---

## 📊 Dashboard Options

### 🟢 Node-RED

* Drag & drop `dashboards/nodered_flow.json` into your Node-RED editor
* Configure MQTT broker to match your local broker

### 🟣 Grafana

* Import `dashboards/grafana_example.json`
* Requires: InfluxDB or similar MQTT→DB bridge

### 🔵 Home Assistant

* Add `dashboards/home_assistant.yaml` to your MQTT discovery directory
* Or use `mqtt:` auto-discovery with matching topics

---

## 🛠️ Dependencies

* `victron-ble2mqtt` Python app: [https://github.com/kwindrem/victron-ble2mqtt](https://github.com/kwindrem/victron-ble2mqtt)
* Python 3.11+
* MQTT broker (Mosquitto recommended)
* Optional: Node-RED, Grafana, Home Assistant

---

## 📮 Contributing

Pull requests welcome for:

* Other dashboard integrations
* Improved systemd handling
* MQTT topic mapping tips

---

## 🧑‍🔧 Maintainer

**Curt Alfrey**
ALFa Quantum Dynamics LLC 
https://alfaqd.com
GitHub: [@curtalfrey](https://github.com/curtalfrey)

---

## 📘 License

MIT License — free to use, modify, and share.

---

## ✅ Coming Soon

* Dockerized version
* Live demo
* Battery SoC/Temp warnings
* SMS/Email alerting hooks

---

Want to share your version? Open an issue or PR!
