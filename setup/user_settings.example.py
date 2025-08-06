"""
user_settings.py
Edit this file to define your Victron BLE devices.
"""

# Set your MQTT connection
mqtt_host = "localhost"
mqtt_port = 1883
mqtt_username = "victron"
mqtt_password = "abc123"   # <- Replace with real pw

# List your Victron BLE devices here
devices = [
    {
        # Victron SmartShunt
        "mac": "abc123",  # <- Replace with real MAC
        "type": "SmartShunt",
        "name": "abc123",
        "advertisement_key": "abc123",   # <- Replace with real key
    },
    {
        # Victron SmartShunt
        "mac": "abc123",  # <- Replace with real MAC
        "type": "SmartShunt",
        "name": "abc123",
        "advertisement_key": "abc123",   # <- Replace with real key
    },
    {
        # Victron MPPT
        "mac": "abc123",  # <- Replace with real MAC
        "type": "BlueSolar",
        "name": "abc123",
        "advertisement_key": "abc123",   # <- Replace with real key
    }
]

# Logging level (optional)
log_level = "INFO"
