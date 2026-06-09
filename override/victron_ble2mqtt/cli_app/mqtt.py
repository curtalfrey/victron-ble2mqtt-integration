"""
CLI for victron-ble2mqtt (patched to use Python user_settings directly).
"""

import asyncio
import logging

from bleak import AdvertisementData, BLEDevice
from cli_base.cli_tools.verbosity import setup_logging
from cli_base.tyro_commands import TyroVerbosityArgType
from ha_services.mqtt4homeassistant.mqtt import get_connected_client
from rich import print  # noqa
from victron_ble.scanner import BaseScanner

from override.victron_ble2mqtt.cli_app import app
from victron_ble2mqtt.cli_app.settings import get_settings
from victron_ble2mqtt.mqtt import VictronMqttDeviceHandler
from victron_ble2mqtt.user_settings import UserSettings
from victron_ble2mqtt.victron_ble_utils import DeviceHandler

logger = logging.getLogger(__name__)


@app.command
def publish_loop(verbosity: TyroVerbosityArgType):
    """
    Publish MQTT messages in endless loop (Entrypoint from systemd)
    """
    setup_logging(verbosity=verbosity)

    # Load Python-based settings (no TOML)
    user_settings: UserSettings = get_settings()

    # Build a list of dicts for DeviceHandler (mac/type/name/advertisement_key)
    keys = [
        {
            'mac': getattr(d, 'mac', None),
            'type': getattr(d, 'type', None),
            'name': getattr(d, 'name', None),
            'advertisement_key': getattr(d, 'advertisement_key', None),
        }
        for d in getattr(user_settings, 'devices', [])
    ]
    print(f'Use device {len(keys)} device keys.')

    class MqttPublisher(BaseScanner):
        def __init__(
            self,
            *,
            keys: list[dict],
            user_settings: UserSettings,
        ):
            super().__init__()
            self.device_handler = DeviceHandler(keys)
            self.victron_mqtt_handler = VictronMqttDeviceHandler(user_settings=user_settings)

            # MQTT client
            self.mqtt_client = get_connected_client(settings=user_settings.mqtt, verbosity=verbosity)
            self.mqtt_client.loop_start()

        # victron-ble 0.9.3: BaseScanner.callback() now receives the bleak
        # AdvertisementData as third argument — RSSI comes straight from it.
        def callback(self, ble_device: BLEDevice, raw_data: bytes, advertisement: AdvertisementData):
            logger.debug(f'Received data from {ble_device.address.lower()}: {raw_data.hex()}')

            if generic_device := self.device_handler.get_generic_device(ble_device, raw_data):
                self.victron_mqtt_handler.publish(
                    ble_device=ble_device,
                    raw_data=raw_data,
                    generic_device=generic_device,
                    rssi=advertisement.rssi,
                    mqtt_client=self.mqtt_client,
                )
            else:
                logger.warning(f'Unsupported: {ble_device.name} ({ble_device.address})')

    async def scan(*, keys: list[dict], user_settings: UserSettings):
        scanner = MqttPublisher(
            keys=keys,
            user_settings=user_settings,
        )
        await scanner.start()

    loop = asyncio.get_event_loop()
    asyncio.ensure_future(
        scan(
            keys=keys,
            user_settings=user_settings,
        )
    )
    loop.run_forever()
