import logging
import socket
import time

from bleak import BLEDevice
from ha_services.mqtt4homeassistant.components.sensor import Sensor
from ha_services.mqtt4homeassistant.device import MainMqttDevice, MqttDevice
from paho.mqtt.client import Client
from victron_ble.devices import BatteryMonitor, Device, SolarCharger

import victron_ble2mqtt
from victron_ble2mqtt.user_settings import UserSettings
from victron_ble2mqtt.victron_ble_utils import GenericDevice

logger = logging.getLogger(__name__)


class BaseHandler:
    VictronDeviceClass = None

    def __init__(
        self,
        *,
        ble_device: BLEDevice,
        main_mqtt_device: MainMqttDevice,
        victron_device: Device,
        mqtt_client: Client,
        user_settings: UserSettings,
    ):
        self.ble_device = ble_device
        self.main_mqtt_device = main_mqtt_device
        self.victron_device = victron_device
        self.mqtt_client = mqtt_client
        self.user_settings = user_settings

        self.device = None
        self.rssi_sensor = None
        self.sensors = {}

    @staticmethod
    def _apply_precision(sensor: Sensor | None, value):
        """Round numeric values based on sensor.suggested_display_precision, if set.
        Preserves non-numeric values.
        """
        try:
            if sensor is None:
                return value
            prec = getattr(sensor, "suggested_display_precision", None)
            if isinstance(value, (int, float)) and isinstance(prec, int):
                if prec == 0:
                    # Use int for whole numbers
                    return int(round(float(value), 0))
                return round(float(value), prec)
        except Exception:
            pass
        return value

    def setup(self, *, data_dict):
        mac_address = self.ble_device.address
        uid = mac_address.lower().replace(":", "")
        # Resolve a friendly, non-empty device name for Home Assistant discovery
        name = self._resolve_device_name(default_uid=uid, data_dict=data_dict)
        self.device = MqttDevice(
            main_device=self.main_mqtt_device,
            name=name,
            uid=uid,
            manufacturer="Victron Energy",
            model=data_dict[
                "model_name"
            ],  # e.g.: 'SmartSolar MPPT 100|20 48V' | 'SmartShunt 500A/50mV',
        )
        self.rssi_sensor = Sensor(
            device=self.device,
            name="RSSI",
            uid="rssi",
            state_class="measurement",
        )

    def _resolve_device_name(self, *, default_uid: str, data_dict: dict) -> str:
        """
        Determine a stable, non-null device name for HA discovery:
        1) use user_settings.devices entry name for matching MAC
        2) else use BLE reported name
        3) else use Victron model_name
        4) else fall back to MAC-based uid
        """
        try:
            mac_l = (self.ble_device.address or "").lower()
            for entry in getattr(self.user_settings, "devices", []) or []:
                try:
                    entry_mac = (getattr(entry, "mac", "") or "").lower()
                    entry_name = getattr(entry, "name", None)
                except Exception:
                    entry_mac = str((entry or {}).get("mac", "")).lower()
                    entry_name = (entry or {}).get("name")
                if entry_mac and entry_mac == mac_l and entry_name:
                    return str(entry_name)
        except Exception:
            pass

        # BLE device name if present
        if getattr(self.ble_device, "name", None):
            return str(self.ble_device.name)

        # Model name from parsed data
        model_name = data_dict.get("model_name")
        if model_name:
            return str(model_name)

        # Final fallback to UID
        return f"Victron {default_uid}"

    def publish(self, *, data_dict: dict, rssi: int | None) -> None:
        if self.device is None:
            self.setup(data_dict=data_dict)
        # Throttle system info polling/publishing
        if not hasattr(self.main_mqtt_device, "_last_sys_poll"):
            self.main_mqtt_device._last_sys_poll = 0.0
        if not hasattr(self.user_settings.mqtt, "system_poll_throttle_seconds"):
            self.user_settings.mqtt.system_poll_throttle_seconds = 3
        now = time.monotonic()
        if (now - self.main_mqtt_device._last_sys_poll) >= float(
            self.user_settings.mqtt.system_poll_throttle_seconds or 3
        ):
            self.main_mqtt_device._last_sys_poll = now
            self.main_mqtt_device.poll_and_publish(self.mqtt_client)

        self.rssi_sensor.set_state(rssi)
        self.rssi_sensor.publish(self.mqtt_client)

        for key, value in data_dict.items():
            if key == "model_name":
                continue

            if sensor := self.sensors.get(key):
                sensor.set_state(self._apply_precision(sensor, value))
                sensor.publish(self.mqtt_client)
            else:
                pass  # logger.warning(f'No sensor for key: {key}')


def calc_midpoint_shift(voltage: float, midpoint_voltage: float) -> float:
    """
    Calculate the midpoint shift in percent.

    >>> calc_midpoint_shift(100, 50)
    0.0
    >>> round(calc_midpoint_shift(26.7, 13.2),3)
    0.15
    >>> round(calc_midpoint_shift(100, 50.1),3)
    0.1
    >>> round(calc_midpoint_shift(100, 49.9),3)
    0.1
    """
    return abs((voltage / 2) - midpoint_voltage)


def calc_midpoint_shift_percent(voltage: float, midpoint_voltage: float) -> float:
    """
    Calculate the midpoint shift in percent.

    >>> calc_midpoint_shift_percent(100, 50)
    0.0
    >>> round(calc_midpoint_shift_percent(26.7, 13.2),3)
    0.89
    >>> calc_midpoint_shift_percent(100, 51)
    0.5
    >>> calc_midpoint_shift_percent(100, 49)
    0.5
    """
    try:
        return abs(voltage / ((midpoint_voltage * 2) - voltage) / 100)
    except ZeroDivisionError:
        return 0.0


class BatteryMonitorHandler(BaseHandler):
    VictronDeviceClass = BatteryMonitor
    # example_data = {
    #     'aux_mode': 'midpoint_voltage',
    #     'consumed_ah': 0.0,
    #     'current': 1.343,
    #     'midpoint_voltage': 13.03,
    #     'model_name': 'SmartShunt 500A/50mV',
    #     'remaining_mins': 65535,
    #     'soc': 100.0,
    #     'voltage': 26.22,
    #     'rssi': -70,
    # }

    def __init__(
        self,
        *,
        ble_device,
        main_mqtt_device,
        victron_device,
        mqtt_client,
        user_settings,
    ):
        # Ensure optional sensors always exist to avoid AttributeError if aux_mode toggles
        super().__init__(
            ble_device=ble_device,
            main_mqtt_device=main_mqtt_device,
            victron_device=victron_device,
            mqtt_client=mqtt_client,
            user_settings=user_settings,
        )
        self.power_sensor = None
        self.midpoint_shift = None
        self.midpoint_shift_percent = None

    def setup(self, *, data_dict):
        super().setup(data_dict=data_dict)

        self.sensors = {
            "aux_mode": Sensor(
                device=self.device,
                name="Auxiliary Mode",
                uid="aux_mode",
            ),
            "consumed_ah": Sensor(
                device=self.device,
                name="Consumed Ah",
                uid="consumed_ah",
                state_class="total_increasing",
                unit_of_measurement="Ah",
                suggested_display_precision=1,
            ),
            "current": Sensor(
                device=self.device,
                name="Current",
                uid="current",
                device_class="current",
                state_class="measurement",
                unit_of_measurement="A",
                suggested_display_precision=3,
            ),
            "midpoint_voltage": Sensor(
                device=self.device,
                name="Midpoint Voltage",
                uid="midpoint_voltage",
                device_class="voltage",
                state_class="measurement",
                unit_of_measurement="V",
                suggested_display_precision=2,
            ),
            "remaining_mins": Sensor(
                device=self.device,
                name="Remaining Minutes",
                uid="remaining_mins",
                state_class="measurement",
                unit_of_measurement="min",
            ),
            "soc": Sensor(
                device=self.device,
                name="State of Charge",
                uid="soc",
                device_class="battery",
                state_class="measurement",
                unit_of_measurement="%",
                suggested_display_precision=1,
            ),
            "voltage": Sensor(
                device=self.device,
                name="Voltage",
                uid="voltage",
                device_class="voltage",
                state_class="measurement",
                unit_of_measurement="V",
                suggested_display_precision=2,
            ),
        }
        ####################################################################################
        # Extra sensors

        self.power_sensor = Sensor(
            device=self.device,
            name="Power",
            uid="power",
            device_class="power",
            state_class="measurement",
            unit_of_measurement="W",
            suggested_display_precision=2,
        )

        if data_dict.get("aux_mode", None) == "midpoint_voltage":
            self.midpoint_shift = Sensor(
                device=self.device,
                name="Midpoint Shift",
                uid="midpoint_shift",
                device_class="voltage",
                state_class="measurement",
                unit_of_measurement="V",
                suggested_display_precision=2,
            )
            self.midpoint_shift_percent = Sensor(
                device=self.device,
                name="Midpoint Shift",
                uid="midpoint_shift_percent",
                state_class="measurement",
                unit_of_measurement="%",
                suggested_display_precision=2,
            )

        # Apply optional per-device precision overrides from user settings
        try:
            mac_l = (self.ble_device.address or "").lower()
            entry = None
            for e in getattr(self.user_settings, "devices", []) or []:
                if getattr(e, "mac", "").lower() == mac_l:
                    entry = e
                    break
            overrides = getattr(entry, "precision", None) if entry else None
            if isinstance(overrides, dict):
                # Map of our internal sensor keys to Sensor objects we created above
                key_to_sensor = {
                    "aux_mode": self.sensors.get("aux_mode"),
                    "consumed_ah": self.sensors.get("consumed_ah"),
                    "current": self.sensors.get("current"),
                    "midpoint_voltage": self.sensors.get("midpoint_voltage"),
                    "remaining_mins": self.sensors.get("remaining_mins"),
                    "soc": self.sensors.get("soc"),
                    "voltage": self.sensors.get("voltage"),
                    "power": self.power_sensor,
                }
                # Include optional midpoint sensors if present
                if self.midpoint_shift:
                    key_to_sensor["midpoint_shift"] = self.midpoint_shift
                if self.midpoint_shift_percent:
                    key_to_sensor["midpoint_shift_percent"] = self.midpoint_shift_percent
                for k, v in overrides.items():
                    try:
                        s = key_to_sensor.get(k)
                        if s is not None and isinstance(v, int):
                            s.suggested_display_precision = v
                    except Exception:
                        pass
        except Exception:
            # Non-fatal if overrides fail
            pass

    def publish(self, *, data_dict: dict, rssi: int | None) -> None:
        super().publish(data_dict=data_dict, rssi=rssi)

        # Extra sensors

        self.power_sensor.set_state(
            self._apply_precision(self.power_sensor, data_dict["voltage"] * data_dict["current"])
        )
        self.power_sensor.publish(self.mqtt_client)

        if data_dict.get("aux_mode", None) == "midpoint_voltage":
            # Lazily create midpoint sensors if aux_mode switched after first packet (__init__ sets None).
            if self.midpoint_shift is None:
                self.midpoint_shift = Sensor(
                    device=self.device,
                    name="Midpoint Shift",
                    uid="midpoint_shift",
                    device_class="voltage",
                    state_class="measurement",
                    unit_of_measurement="V",
                    suggested_display_precision=2,
                )
                self.midpoint_shift_percent = Sensor(
                    device=self.device,
                    name="Midpoint Shift",
                    uid="midpoint_shift_percent",
                    state_class="measurement",
                    unit_of_measurement="%",
                    suggested_display_precision=2,
                )
                # Apply precision overrides if configured for this device
                try:
                    mac_l = (self.ble_device.address or "").lower()
                    entry = None
                    for e in getattr(self.user_settings, "devices", []) or []:
                        if getattr(e, "mac", "").lower() == mac_l:
                            entry = e
                            break
                    overrides = getattr(entry, "precision", None) if entry else None
                    if isinstance(overrides, dict):
                        if "midpoint_shift" in overrides and isinstance(
                            overrides["midpoint_shift"], int
                        ):
                            self.midpoint_shift.suggested_display_precision = overrides[
                                "midpoint_shift"
                            ]
                        if "midpoint_shift_percent" in overrides and isinstance(
                            overrides["midpoint_shift_percent"], int
                        ):
                            self.midpoint_shift_percent.suggested_display_precision = overrides[
                                "midpoint_shift_percent"
                            ]
                except Exception:
                    pass
            midpoint_shift = calc_midpoint_shift(
                data_dict["voltage"], data_dict["midpoint_voltage"]
            )
            self.midpoint_shift.set_state(
                self._apply_precision(self.midpoint_shift, midpoint_shift)
            )
            self.midpoint_shift.publish(self.mqtt_client)

            midpoint_shift_percent = calc_midpoint_shift_percent(
                data_dict["voltage"], data_dict["midpoint_voltage"]
            )
            self.midpoint_shift_percent.set_state(
                self._apply_precision(self.midpoint_shift_percent, midpoint_shift_percent)
            )
            self.midpoint_shift_percent.publish(self.mqtt_client)


class SolarChargerHandler(BaseHandler):
    VictronDeviceClass = SolarCharger
    # example_data = {
    #     'battery_charging_current': 0.8,
    #     'battery_voltage': 25.91,
    #     'charge_state': 'bulk',
    #     'external_device_load': 0.0,
    #     'model_name': 'SmartSolar MPPT 100|20 48V',
    #     'solar_power': 22,
    #     'yield_today': 330,
    #     'rssi': -80,
    # }

    def setup(self, *, data_dict):
        super().setup(data_dict=data_dict)

        self.sensors = {
            "battery_charging_current": Sensor(
                device=self.device,
                name="Battery Charging",
                uid="battery_charging_current",
                device_class="current",
                state_class="measurement",
                unit_of_measurement="A",
                suggested_display_precision=1,
            ),
            "battery_voltage": Sensor(
                device=self.device,
                name="Battery",
                uid="battery_voltage",
                device_class="voltage",
                state_class="measurement",
                unit_of_measurement="V",
                suggested_display_precision=2,
            ),
            "charge_state": Sensor(
                device=self.device,
                uid="charge_state",
                name="Charge State",
            ),
            "external_device_load": Sensor(
                device=self.device,
                name="Load",
                uid="load",
                device_class="current",
                state_class="measurement",
                unit_of_measurement="A",
                suggested_display_precision=1,
            ),
            "solar_power": Sensor(
                device=self.device,
                name="Solar",
                uid="solar_power",
                device_class="power",
                state_class="measurement",
                unit_of_measurement="W",
                suggested_display_precision=0,
            ),
            "yield_today": Sensor(
                device=self.device,
                name="Yield Today",
                uid="yield_today",
                device_class="energy",
                state_class="total_increasing",
                unit_of_measurement="Wh",
                suggested_display_precision=0,
            ),
        }
        ####################################################################################
        # Extra sensors

        self.charging_power = Sensor(
            device=self.device,
            name="Charging Power",
            uid="charging_power",
            device_class="power",
            state_class="measurement",
            unit_of_measurement="W",
            suggested_display_precision=1,
        )
        self.load_power = Sensor(
            device=self.device,
            name="Load Power",
            uid="load_power",
            device_class="power",
            state_class="measurement",
            unit_of_measurement="W",
            suggested_display_precision=1,
        )

    def publish(self, *, data_dict: dict, rssi: int | None) -> None:
        super().publish(data_dict=data_dict, rssi=rssi)

        # Extra sensors

        self.charging_power.set_state(
            self._apply_precision(
                self.charging_power,
                data_dict["battery_voltage"] * data_dict["battery_charging_current"],
            )
        )
        self.charging_power.publish(self.mqtt_client)

        self.load_power.set_state(
            self._apply_precision(
                self.load_power,
                data_dict["battery_voltage"] * data_dict["external_device_load"],
            )
        )
        self.load_power.publish(self.mqtt_client)


class FallbackHandler(BaseHandler):
    VictronDeviceClass = None

    def setup(self, *, data_dict):
        super().setup(data_dict=data_dict)

        for key in data_dict.keys():
            if key == "model_name":
                continue

            logger.warning("Setup fallback sensor for: %s", key)

            self.sensors[key] = Sensor(
                device=self.device,
                name=key.capitalize(),
                uid=key,
            )


VICRON_DEVICE_HANDLERS = (
    BatteryMonitorHandler,
    SolarChargerHandler,
)


def get_handler(*, victron_device: Device) -> type[BaseHandler]:
    for HandlerClass in VICRON_DEVICE_HANDLERS:
        if isinstance(victron_device, HandlerClass.VictronDeviceClass):
            logger.info("Handler for %s: %s", victron_device, HandlerClass.__name__)
            return HandlerClass

    logger.warning("Use fallback handler for %s", victron_device)
    return FallbackHandler


class VictronMqttDeviceHandler:
    def __init__(self, *, user_settings: UserSettings):
        self.user_settings = user_settings
        self.main_mqtt_device = MainMqttDevice(
            name=f"victron-ble2mqtt@{socket.gethostname()}",
            uid=user_settings.mqtt.main_uid,
            manufacturer="victron-ble2mqtt",
            sw_version=victron_ble2mqtt.__version__,
            config_throttle_sec=user_settings.mqtt.publish_config_throttle_seconds,
        )
        self.handler_map = {}

    def publish(
        self,
        *,
        ble_device: BLEDevice,
        raw_data: bytes,
        generic_device: GenericDevice,
        rssi: int | None,
        mqtt_client: Client,
    ) -> None:
        logger.debug("MQTT data from %s", ble_device.name)

        mac_address = ble_device.address
        try:
            handler = self.handler_map[mac_address]
        except KeyError:
            HandlerClass = get_handler(victron_device=generic_device.victron_device)
            handler = self.handler_map[mac_address] = HandlerClass(
                ble_device=ble_device,
                main_mqtt_device=self.main_mqtt_device,
                victron_device=generic_device.victron_device,
                mqtt_client=mqtt_client,
                user_settings=self.user_settings,
            )

        handler.publish(
            data_dict=generic_device.parse(raw_data=raw_data),
            rssi=rssi,
        )
