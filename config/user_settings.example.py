"""
user_settings.example.py
Edit this file and copy it to `victron_ble2mqtt/user_settings.py`
"""

# Set your MQTT connection
mqtt_host = "localhost"
mqtt_port = 1883
mqtt_username = "your-username"
mqtt_password = "your-password"

# List your Victron BLE devices here
devices = [
    {
        # Victron SmartShunt
        "mac": "XX:XX:XX:XX:XX:XX",  # <- Replace with real MAC
        "type": "SmartShunt",
        "name": "Battery 1",
        "advertisement_key": "your_advertisement_key"
    },
    {
        # Victron MPPT
        "mac": "YY:YY:YY:YY:YY:YY",
        "type": "BlueSolar",
        "name": "Solar 1",
        "advertisement_key": "your_advertisement_key"
    }
]

# Logging level (optional)
log_level = "INFO"
