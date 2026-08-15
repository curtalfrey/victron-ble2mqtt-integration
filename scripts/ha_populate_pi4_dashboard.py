#!/usr/bin/env python3
"""Populate the Pi4 Lovelace dashboard with victron-ble2mqtt host metrics."""
import json
from pathlib import Path

STORAGE = Path("/opt/homeassistant/.storage/lovelace.dashboard_pi4")

SECTIONS = [
    ("System", [
        "sensor.victron_ble2mqtt_pi4_hostname",
        "sensor.victron_ble2mqtt_pi4_system_up_time",
        "sensor.victron_ble2mqtt_pi4_total_cpu_usage",
        "sensor.victron_ble2mqtt_pi4_process_cpu_usage",
        "sensor.victron_ble2mqtt_pi4_system_load_1min",
        "sensor.victron_ble2mqtt_pi4_temperature_cpu_thermal",
        "sensor.victron_ble2mqtt_pi4_swap_usage",
        "sensor.victron_ble2mqtt_pi4_cpu_frequency",
    ]),
    ("Wi-Fi", [
        "sensor.victron_ble2mqtt_pi4_wifi_device_name",
        "sensor.victron_ble2mqtt_pi4_essid",
        "sensor.victron_ble2mqtt_pi4_signal_level",
        "sensor.victron_ble2mqtt_pi4_link_quality",
        "sensor.victron_ble2mqtt_pi4_frequency",
        "sensor.victron_ble2mqtt_pi4_bit_rate",
    ]),
    ("Network", [
        "sensor.victron_ble2mqtt_pi4_wlan0_received_rate",
        "sensor.victron_ble2mqtt_pi4_wlan0_sent_rate",
        "sensor.victron_ble2mqtt_pi4_eth0_received_rate",
        "sensor.victron_ble2mqtt_pi4_eth0_sent_rate",
        "sensor.victron_ble2mqtt_pi4_tailscale0_received_rate",
        "sensor.victron_ble2mqtt_pi4_tailscale0_sent_rate",
    ]),
]


def tile(entity_id: str) -> dict:
    return {"type": "tile", "entity": entity_id}


def section(title: str, entities: list[str]) -> dict:
    cards = [{"type": "heading", "heading": title}]
    cards.extend(tile(e) for e in entities)
    return {"type": "grid", "cards": cards, "column_span": 3}


data = {
    "version": 1,
    "minor_version": 1,
    "key": "lovelace.dashboard_pi4",
    "data": {
        "config": {
            "views": [
                {
                    "title": "Pi4",
                    "type": "sections",
                    "sections": [section(title, entities) for title, entities in SECTIONS],
                }
            ]
        }
    },
}

STORAGE.parent.mkdir(parents=True, exist_ok=True)
STORAGE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"wrote {STORAGE}")
