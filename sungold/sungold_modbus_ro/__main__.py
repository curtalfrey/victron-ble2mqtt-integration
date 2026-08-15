"""Entry point: poll SRNE registers and publish read-only HA MQTT discovery."""

from __future__ import annotations

import os
import signal
import sys
import time

from .config import load_settings
from .modbus_io import ReadOnlyModbusClient
from .mqtt_ha import MqttHaPublisher
from .registers import CURATED_ENTITIES


def main() -> int:
    settings = load_settings()
    print(
        f"sungold_modbus_ro: address={settings.modbus_address} "
        f"device={settings.modbus_device} topic={settings.mqtt_topic}"
    )

    modbus = ReadOnlyModbusClient(settings)
    mqtt_pub = MqttHaPublisher(settings)
    mqtt_pub.connect_with_retry()
    mqtt_pub.client.loop_start()

    running = True

    def _stop(signum, frame) -> None:
        nonlocal running
        print("\nShutdown requested")
        running = False

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    time.sleep(1.0)

    while running:
        published_any = False
        for entity in CURATED_ENTITIES:
            if not modbus.is_register_available(entity.register):
                if entity.key not in mqtt_pub._hidden:
                    mqtt_pub.hide_entity(entity)
                continue
            if entity.key in mqtt_pub._hidden:
                mqtt_pub.restore_entity(entity)

            value = modbus.read_entity(entity)
            if value is None:
                continue
            mqtt_pub.publish_state(entity, value)
            published_any = True

        if published_any:
            try:
                with open(settings.heartbeat_file, "a", encoding="utf-8"):
                    pass
                os.utime(settings.heartbeat_file, None)
            except OSError as exc:
                print(f"Heartbeat touch failed: {exc}")

        modbus.check_reconnect()
        time.sleep(settings.poll_interval_sec)

    mqtt_pub.client.loop_stop()
    mqtt_pub.client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
