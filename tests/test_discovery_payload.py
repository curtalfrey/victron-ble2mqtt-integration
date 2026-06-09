"""Regression lock for Home Assistant Core 2026.4 MQTT discovery changes.

HA deprecated the MQTT discovery option ``object_id`` in favor of
``default_entity_id`` (home-assistant/core#151775) and removed it in
HA Core 2026.4 (home-assistant/core#164460). A payload that still contains
``object_id`` is rejected by current HA.

ha-services (which owns this bridge's discovery payload shape) never emitted
``object_id`` — verified by source inspection of 2.12.0 and 2.15.2 — so the
bridge is compatible. These tests pin that fact against future upgrades.
"""

import json

from ha_services.mqtt4homeassistant.components.sensor import Sensor
from ha_services.mqtt4homeassistant.device import MqttDevice

# Keys HA 2026.4 rejects in MQTT discovery payloads
REMOVED_DISCOVERY_KEYS = ('object_id', 'obj_id')


def _make_sensor(device_uid: str) -> Sensor:
    # Mirrors how override/victron_ble2mqtt/mqtt.py BaseHandler.setup() builds sensors
    device = MqttDevice(
        name='Victron Test Device',
        uid=device_uid,
        manufacturer='Victron Energy',
        model='SmartShunt 500A/50mV',
    )
    return Sensor(
        device=device,
        name='Voltage',
        uid='voltage',
        device_class='voltage',
        state_class='measurement',
        unit_of_measurement='V',
        suggested_display_precision=2,
    )


def test_discovery_config_contains_no_removed_object_id():
    sensor = _make_sensor('victron_test_discovery1')

    payload = sensor.get_config().payload

    for removed_key in REMOVED_DISCOVERY_KEYS:
        assert removed_key not in payload
        assert removed_key not in payload['device']
    # Registry stability comes from unique_id (entity IDs are preserved in HA
    # registry once discovered)
    assert payload['unique_id'] == 'victron_test_discovery1-voltage'


def test_discovery_wire_payload_contains_no_removed_object_id():
    """Assert on the exact JSON published to homeassistant/.../config."""
    sensor = _make_sensor('victron_test_discovery2')

    config_kwargs = sensor._get_config_kwargs()
    assert config_kwargs['topic'].endswith('/config')

    wire_payload = json.loads(config_kwargs['payload'])
    for removed_key in REMOVED_DISCOVERY_KEYS:
        assert removed_key not in wire_payload
        assert removed_key not in wire_payload['device']
    assert wire_payload['unique_id'] == 'victron_test_discovery2-voltage'
    assert wire_payload['state_topic'].endswith('/state')
