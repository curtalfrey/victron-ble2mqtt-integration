import importlib
import os
import socket
from dataclasses import dataclass, field
from typing import Any, Optional

from ha_services.mqtt4homeassistant.utilities.string_utils import slugify


@dataclass
class MqttConfig:
    host: str = "localhost"
    port: int = 1883
    username: Optional[str] = None
    user_name: Optional[str] = None
    password: Optional[str] = None
    tls: bool = False
    ca_file: Optional[str] = None
    main_uid: Optional[str] = None
    publish_config_throttle_seconds: int = 60
    # New throttles
    publish_throttle_seconds: int = 3  # min gap between device publishes
    system_poll_throttle_seconds: int = 3  # min gap between system info polls
    log_throttle_seconds: int = 3  # min gap between repeated debug/warn logs


@dataclass
class DeviceEntry:
    mac: str
    type: Optional[str] = None
    name: Optional[str] = None
    advertisement_key: Optional[str] = None
    # Optional per-device precision overrides: { sensor_key: int }
    # Known sensor keys for BatteryMonitor: 'voltage', 'current', 'power', 'soc',
    # 'consumed_ah', 'midpoint_voltage', 'midpoint_shift', 'midpoint_shift_percent', 'remaining_mins'
    precision: Optional[dict[str, int]] = None


@dataclass
class UserSettings:
    mqtt: MqttConfig = field(default_factory=MqttConfig)
    devices: list[DeviceEntry] = field(default_factory=list)

    def __post_init__(self) -> None:
        data = importlib.import_module("victron_ble2mqtt.user_settings_data")
        try:
            data = importlib.reload(data)
        except Exception:
            pass
        # Base connection params
        self.mqtt.host = getattr(data, "mqtt_host", self.mqtt.host)
        self.mqtt.port = int(getattr(data, "mqtt_port", self.mqtt.port))

        # Username/password from data or environment
        self.mqtt.username = getattr(data, "mqtt_username", None) or os.getenv("MQTT_USER") or None
        self.mqtt.user_name = getattr(data, "mqtt_username", None) or self.mqtt.username
        self.mqtt.password = getattr(data, "mqtt_password", None) or (
            os.getenv("MQTT_PASSWORD") if (self.mqtt.username or os.getenv("MQTT_USER")) else None
        )

        # Main UID and throttles (ha_services requires uid == slugify(uid); hostnames may contain '-')
        _raw_main = (
            getattr(data, "main_uid", None)
            or os.getenv("MAIN_UID")
            or socket.gethostname()
            or "victron"
        )
        self.mqtt.main_uid = slugify(str(_raw_main).strip(), sep="_")

        pcs = getattr(data, "publish_config_throttle_seconds", None) or os.getenv(
            "PUBLISH_CONFIG_THROTTLE_SEC"
        )
        if pcs not in (None, ""):
            try:
                self.mqtt.publish_config_throttle_seconds = int(pcs)
            except Exception:
                pass

        # Optional throttles
        pths = getattr(data, "publish_throttle_seconds", None) or os.getenv("PUBLISH_THROTTLE_SEC")
        if pths not in (None, ""):
            try:
                self.mqtt.publish_throttle_seconds = int(pths)
            except Exception:
                pass

        sths = getattr(data, "system_poll_throttle_seconds", None) or os.getenv(
            "SYSTEM_POLL_THROTTLE_SEC"
        )
        if sths not in (None, ""):
            try:
                self.mqtt.system_poll_throttle_seconds = int(sths)
            except Exception:
                pass

        lths = getattr(data, "log_throttle_seconds", None) or os.getenv("LOG_THROTTLE_SEC")
        if lths not in (None, ""):
            try:
                self.mqtt.log_throttle_seconds = int(lths)
            except Exception:
                pass

        # Device list normalization
        raw_devices: list[dict[str, Any]] = list(getattr(data, "devices", []))
        norm: list[DeviceEntry] = []
        for d in raw_devices:
            if isinstance(d, dict):
                norm.append(
                    DeviceEntry(
                        mac=str(d.get("mac", "")),
                        type=d.get("type"),
                        name=d.get("name"),
                        advertisement_key=d.get("advertisement_key"),
                        precision=d.get("precision"),
                    )
                )
        self.devices = norm
