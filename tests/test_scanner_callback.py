from unittest.mock import Mock
import types

from victron_ble2mqtt.test_helpers import MqttPublisherHelper


def test_callback_routes_to_publish():
    calls = {}

    class DummyDeviceHandler:
        def get_generic_device(self, ble_device, raw_data):
            calls['get_generic_device'] = True
            class G:
                def __init__(self):
                    self.victron_device = object()
                def parse(self, raw_data):
                    return {'model_name': 'X', 'voltage': 12}
            return G()

    class DummyMqttHandler:
        def publish(self, *, ble_device, raw_data, generic_device, rssi, mqtt_client):
            calls['published'] = True
            calls['rssi'] = rssi

    device_handler = DummyDeviceHandler()
    victron_mqtt_handler = DummyMqttHandler()
    mqtt_client = Mock()

    pub = MqttPublisherHelper(
        keys=[],
        device_handler=device_handler,
        victron_mqtt_handler=victron_mqtt_handler,
        mqtt_client=mqtt_client,
    )

    FakeBLE = types.SimpleNamespace(address='AA:BB:CC:11:22:33', name='FAKE')
    FakeAdv = types.SimpleNamespace(rssi=-66)

    # victron-ble 0.9.3 passes the AdvertisementData as third callback argument
    pub.callback(FakeBLE, b'\x01', FakeAdv)

    assert calls.get('get_generic_device') is True
    assert calls.get('published') is True
    assert calls.get('rssi') == -66
