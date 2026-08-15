"""Unit tests for Sungold read-only MQTT discovery (no hardware)."""

from __future__ import annotations

import json

from sungold_modbus_ro.config import Settings
from sungold_modbus_ro.mqtt_ha import MqttHaPublisher
from sungold_modbus_ro.registers import (
    CURATED_ENTITIES,
    decode_failcode,
    decode_fault_binary,
)


def _settings() -> Settings:
    return Settings(
        modbus_device="/dev/null",
        modbus_address=1,
        modbus_baudrate=9600,
        modbus_timeout=0.25,
        modbus_skip_threshold=5,
        modbus_skip_retry_interval=3600,
        mqtt_host="127.0.0.1",
        mqtt_port=1883,
        mqtt_user="test",
        mqtt_password="test",
        mqtt_topic="sungold_sph302480a",
        device_name="Sungold SPH302480A",
        poll_interval_sec=5,
        heartbeat_file="/tmp/sungold_test.heartbeat",
        skip_state_file="/tmp/sungold_test_skip.json",
    )


def test_curated_entities_are_read_only_sensors():
    allowed = {"sensor", "binary_sensor"}
    keys = [e.key for e in CURATED_ENTITIES]
    assert len(keys) == len(set(keys)), "duplicate entity keys"
    for entity in CURATED_ENTITIES:
        assert entity.topic_type in allowed
        assert entity.register > 0


def test_discovery_payload_has_unique_id_not_object_id():
    pub = MqttHaPublisher(_settings())
    entity = next(e for e in CURATED_ENTITIES if e.key == "battery/soc")
    payload = pub.build_discovery_payload(entity)
    wire = json.loads(json.dumps(payload))
    assert "unique_id" in wire
    assert wire["unique_id"] == "sungold_sph302480a-battery-soc"
    assert "object_id" not in wire
    assert wire["state_topic"] == "sungold_sph302480a/sensor/battery/soc/state"
    assert wire["device"]["model"] == "SPH302480A"


def test_failcode_decoding():
    assert decode_failcode(0) == "No reported error"
    assert "undervoltage" in decode_failcode(1).lower()
    assert decode_fault_binary(0) == "OFF"
    assert decode_fault_binary(14) == "ON"
