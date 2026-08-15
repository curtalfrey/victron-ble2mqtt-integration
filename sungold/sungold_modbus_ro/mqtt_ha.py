"""Home Assistant MQTT discovery publisher (sensors and binary_sensors only)."""

from __future__ import annotations

import json
import time
from typing import TYPE_CHECKING

import paho.mqtt.client as mqtt

from .registers import CURATED_ENTITIES, EntityDef

if TYPE_CHECKING:
    from .config import Settings


class MqttHaPublisher:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._device = {
            "identifiers": [settings.mqtt_topic],
            "name": settings.device_name,
            "manufacturer": "Sungold",
            "model": "SPH302480A",
        }
        self._hidden: set[str] = set()
        self._client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, protocol=mqtt.MQTTv311)
        self._client.username_pw_set(settings.mqtt_user, settings.mqtt_password)
        self._client.on_connect = self._on_connect

    @property
    def client(self) -> mqtt.Client:
        return self._client

    def connect_with_retry(self) -> None:
        delay = 1.0
        while True:
            try:
                self._client.connect(self._settings.mqtt_host, self._settings.mqtt_port)
                return
            except OSError as exc:
                print(f"MQTT connection failed: {exc} — retrying in {delay:.0f}s")
                time.sleep(delay)
                delay = min(delay * 2, 60.0)

    def _on_connect(self, client, userdata, connect_flags, reason_code, properties) -> None:
        if reason_code.is_failure:
            print(f"MQTT connect failed: {reason_code}")
            return
        print(f"MQTT connected ({reason_code})")
        for entity in CURATED_ENTITIES:
            self.publish_discovery(entity)

    def _field_name(self, entity: EntityDef) -> str:
        return f"{self._settings.mqtt_topic}-{entity.key.replace('/', '-')}"

    def _state_topic(self, entity: EntityDef) -> str:
        return f"{self._settings.mqtt_topic}/{entity.topic_type}/{entity.key}/state"

    def discovery_topic(self, entity: EntityDef) -> str:
        return f"homeassistant/{entity.topic_type}/{self._field_name(entity)}/config"

    def build_discovery_payload(self, entity: EntityDef) -> dict:
        payload: dict = {
            "name": entity.name,
            "unique_id": self._field_name(entity),
            "device": self._device,
            "state_topic": self._state_topic(entity),
        }
        if entity.icon:
            payload["icon"] = entity.icon
        if entity.device_class:
            payload["device_class"] = entity.device_class
        if entity.state_class:
            payload["state_class"] = entity.state_class
        if entity.unit:
            payload["unit_of_measurement"] = entity.unit
        if entity.entity_category:
            payload["entity_category"] = entity.entity_category
        if entity.topic_type == "binary_sensor":
            payload["payload_on"] = "ON"
            payload["payload_off"] = "OFF"
        return payload

    def publish_discovery(self, entity: EntityDef) -> None:
        topic = self.discovery_topic(entity)
        payload = json.dumps(self.build_discovery_payload(entity))
        self._client.publish(topic, payload, retain=True)

    def hide_entity(self, entity: EntityDef) -> None:
        if entity.key in self._hidden:
            return
        self._hidden.add(entity.key)
        self._client.publish(self.discovery_topic(entity), "", retain=True)
        print(f"Disabled HA entity for unsupported register: {entity.key}")

    def restore_entity(self, entity: EntityDef) -> None:
        if entity.key not in self._hidden:
            return
        self._hidden.discard(entity.key)
        self.publish_discovery(entity)
        print(f"Restored HA entity: {entity.key}")

    def publish_state(self, entity: EntityDef, value: str) -> None:
        self._client.publish(self._state_topic(entity), value, retain=False)
