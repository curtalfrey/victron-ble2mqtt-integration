import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from write_theengs_mqtt_env import effective_mqtt_host, mqtt_env_body, parse_dotenv


def test_maps_mqtt_user_and_replaces_loopback() -> None:
    data = parse_dotenv(
        "MQTT_HOST=127.0.0.1\nMQTT_USER=victron\nMQTT_PASSWORD=secret\nMQTT_PORT=1883\n"
    )
    body = mqtt_env_body(data, "192.168.0.223")
    assert "MQTT_HOST=192.168.0.223" in body
    assert "MQTT_USERNAME=victron" in body
    assert "MQTT_PASSWORD=secret" in body
    assert "MQTT_PORT=1883" in body


def test_keeps_explicit_lan_host() -> None:
    assert effective_mqtt_host("192.168.0.223", "10.0.0.1") == "192.168.0.223"


def test_placeholder_uses_fallback() -> None:
    assert effective_mqtt_host("192.168.0.XX", "192.168.0.223") == "192.168.0.223"
