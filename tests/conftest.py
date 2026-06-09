import os
import socket
import shutil
import subprocess
import time
import warnings

import pytest
import sys
from pathlib import Path

# Ensure repo root is on sys.path for local test runs
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Suppress paho-mqtt callback API deprecation warnings during tests
warnings.filterwarnings(
    "ignore",
    category=DeprecationWarning,
    message=r".*Callback API version.*",
)


@pytest.fixture(autouse=True)
def _isolate_ha_services_global_registry():
    """Reset ha-services' global component/device registry between tests.

    ha-services 2.13.0 made the component registry global (class-level on
    BaseMqttDevice), so two tests creating devices with the same uid hit
    'Duplicate component' assertions. Upstream added a cleanup method in
    2.15.4 (jedie/ha-services#103), but 2.15.4 requires Python >=3.12 and we
    pin 2.15.2 (image/CI run 3.11) — reset the class-level state directly.
    """
    try:
        from ha_services.mqtt4homeassistant.device import BaseMqttDevice
    except ImportError:
        yield
        return
    saved_components = dict(BaseMqttDevice.components)
    saved_uids = set(BaseMqttDevice.device_uids)
    yield
    BaseMqttDevice.components.clear()
    BaseMqttDevice.components.update(saved_components)
    BaseMqttDevice.device_uids.clear()
    BaseMqttDevice.device_uids.update(saved_uids)


def _is_port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.5):
            return True
    except Exception:
        return False


@pytest.fixture(scope="session", autouse=True)
def ensure_mqtt_broker():
    """Ensure an MQTT broker is available on localhost:1883 for integration tests.

    Behavior:
    - If localhost:1883 is already open, do nothing.
    - Else if docker is available, start a temporary eclipse-mosquitto container
      bound to 1883 and stop it after the test session.
    - Else skip the test session (integration tests require a broker).
    """
    host = os.environ.get("MQTT_HOST", "localhost")
    port = int(os.environ.get("MQTT_PORT", 1883))

    if _is_port_open(host, port):
        # Broker already available on requested host/port
        yield
        return

    docker = shutil.which("docker")
    if not docker:
        pytest.skip("No MQTT broker on localhost:1883 and Docker not available to start one.")

    # Try to start a lightweight mosquitto container
    container_id = None
    try:
        # Use host networking so mosquitto listens on host interfaces
        container_id = subprocess.check_output([
            "docker",
            "run",
            "--rm",
            "-d",
            "--network",
            "host",
            "eclipse-mosquitto:2.0",
        ], stderr=subprocess.STDOUT)
        container_id = container_id.decode().strip()
    except subprocess.CalledProcessError as exc:
        pytest.skip(f"Failed to start mosquitto container for tests: {exc.output.decode(errors='ignore')}")

    # Wait for broker to accept connections and respond to a pub/sub
    deadline = time.time() + 15
    ready = False
    try:
        import paho.mqtt.client as mqtt
        from paho.mqtt.enums import CallbackAPIVersion
        import threading

        # Attempt multiple times to ensure broker is ready and delivers messages
        attempt_deadline = time.time() + 15
        while time.time() < attempt_deadline:
            if not _is_port_open(host, port):
                time.sleep(0.2)
                continue

            connected_evt = threading.Event()
            subscribed_evt = threading.Event()
            received_evt = threading.Event()

            def on_connect(client, userdata, flags, reason_code, properties=None):
                try:
                    client.subscribe("victron/test-ready")
                except Exception:
                    pass
                connected_evt.set()

            def on_subscribe(client, userdata, mid, reason_codes, properties=None):
                subscribed_evt.set()

            def on_message(client, userdata, msg):
                received_evt.set()

            client = mqtt.Client(callback_api_version=CallbackAPIVersion.VERSION2)
            client.on_connect = on_connect
            client.on_subscribe = on_subscribe
            client.on_message = on_message

            try:
                client.connect(host, port, 60)
                client.loop_start()

                # Wait up to 3s for connect+subscribe
                if not connected_evt.wait(timeout=3.0):
                    client.loop_stop()
                    time.sleep(0.2)
                    continue

                if not subscribed_evt.wait(timeout=3.0):
                    # If subscription not acknowledged, try again
                    client.loop_stop()
                    time.sleep(0.2)
                    continue

                # Publish and wait for message to be echoed back
                client.publish("victron/test-ready", payload="ready", qos=0)
                if received_evt.wait(timeout=2.0):
                    ready = True
                    client.loop_stop()
                    break

                client.loop_stop()
                time.sleep(0.2)
            except Exception:
                try:
                    client.loop_stop()
                except Exception:
                    pass
                time.sleep(0.2)
                continue
    except Exception:
        # If paho not available, fall back to port check only
        while time.time() < deadline and not _is_port_open(host, port):
            time.sleep(0.2)

    if not ready and not _is_port_open(host, port):
        # Stop container if it started but broker not reachable
        try:
            if container_id:
                subprocess.run(["docker", "stop", container_id], check=False, stdout=subprocess.DEVNULL)
        finally:
            pytest.skip("Could not start a mosquitto broker for integration tests.")

    try:
        yield
    finally:
        # Stop the container we started (container was created with --rm so it will be removed)
        if container_id:
            subprocess.run(["docker", "stop", container_id], check=False, stdout=subprocess.DEVNULL)


def _is_integration_test(item):
    # treat files named test_integration_*.py as integration tests
    try:
        name = item.fspath.basename
    except Exception:
        name = str(item.fspath)
    return name.startswith("test_integration") or "integration" in name.lower()


def pytest_runtest_setup(item):
    if _is_integration_test(item):
        s = socket.socket()
        s.settimeout(0.25)
        try:
            s.connect(("127.0.0.1", 1883))
            s.close()
        except Exception:
            pytest.skip("Skipping integration test: MQTT broker not available on localhost:1883")
