"""Test helpers: a test-friendly MqttPublisher extracted from the CLI nested class.

This class mirrors the behaviour needed for tests without inheriting BaseScanner or
starting event loops. Use dependency injection to supply mocks for DeviceHandler,
VictronMqttDeviceHandler and mqtt_client.
"""
from typing import Any


class MqttPublisherHelper:
    def __init__(
        self,
        *,
        keys: list[dict],
        user_settings=None,
        device_handler=None,
        victron_mqtt_handler=None,
        mqtt_client=None,
    ):
        # Allow tests to inject mocks; otherwise create real handlers if available
        self.device_handler = device_handler
        self.victron_mqtt_handler = victron_mqtt_handler
        self.mqtt_client = mqtt_client

    # victron-ble 0.9.3: BaseScanner.callback() receives the bleak
    # AdvertisementData as third argument — RSSI comes straight from it.
    def callback(self, ble_device: Any, raw_data: bytes, advertisement: Any):
        # emulate the CLI behavior: ask device_handler for generic device
        generic_device = None
        if self.device_handler is not None:
            try:
                generic_device = self.device_handler.get_generic_device(ble_device, raw_data)
            except Exception:
                generic_device = None

        if generic_device and self.victron_mqtt_handler is not None:
            self.victron_mqtt_handler.publish(
                ble_device=ble_device,
                raw_data=raw_data,
                generic_device=generic_device,
                rssi=getattr(advertisement, 'rssi', None),
                mqtt_client=self.mqtt_client,
            )
        else:
            # In production it logs a warning; in tests we just return
            return None
