# Example user_settings.py for victron-ble2mqtt

BLE_DEVICES = {
    "temp_sensor": {
        "mac": "AA:BB:CC:DD:EE:01",
        "type": "temp"
    },
    "mppt_1": {
        "mac": "AA:BB:CC:DD:EE:02",
        "type": "victron"
    },
    "shunt_1": {
        "mac": "AA:BB:CC:DD:EE:03",
        "type": "victron"
    }
}

MQTT = {
    "host": "localhost",
    "port": 1883,
    "topic_prefix": "victron",
    "client_id": "victron_ble2mqtt"
}
