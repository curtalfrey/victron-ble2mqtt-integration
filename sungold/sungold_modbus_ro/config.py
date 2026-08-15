"""Environment-driven configuration."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    modbus_device: str
    modbus_address: int
    modbus_baudrate: int
    modbus_timeout: float
    modbus_skip_threshold: int
    modbus_skip_retry_interval: float
    mqtt_host: str
    mqtt_port: int
    mqtt_user: str
    mqtt_password: str
    mqtt_topic: str
    device_name: str
    poll_interval_sec: float
    heartbeat_file: str
    skip_state_file: str


def load_settings() -> Settings:
    user = os.getenv("MQTT_USER") or os.getenv("MQTT_USERNAME") or ""
    password = os.getenv("MQTT_PASSWORD") or ""
    if not user or not password:
        raise ValueError("MQTT_USER/MQTT_USERNAME and MQTT_PASSWORD must be set")

    return Settings(
        modbus_device=os.getenv("MODBUS_DEVICE", "/dev/sungold"),
        modbus_address=int(os.getenv("MODBUS_ADDRESS", "1")),
        modbus_baudrate=int(os.getenv("MODBUS_BAUDRATE", "9600")),
        modbus_timeout=float(os.getenv("MODBUS_TIMEOUT", "0.25")),
        modbus_skip_threshold=int(os.getenv("MODBUS_SKIP_THRESHOLD", "5")),
        modbus_skip_retry_interval=float(os.getenv("MODBUS_SKIP_RETRY_INTERVAL", "3600")),
        mqtt_host=os.getenv("MQTT_HOST", "127.0.0.1"),
        mqtt_port=int(os.getenv("MQTT_PORT", "1883")),
        mqtt_user=user,
        mqtt_password=password,
        mqtt_topic=os.getenv("MQTT_TOPIC", "sungold_sph302480a"),
        device_name=os.getenv("DEVICE_NAME", "Sungold SPH302480A"),
        poll_interval_sec=float(os.getenv("POLL_INTERVAL_SEC", "5")),
        heartbeat_file=os.getenv("HEARTBEAT_FILE", "/tmp/sungold_modbus_ro.heartbeat"),
        skip_state_file=os.getenv("MODBUS_SKIP_STATE_FILE", "/tmp/sungold_register_skip_state.json"),
    )
