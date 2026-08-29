#!/usr/bin/env python3
"""Write Theengs Gateway mqtt.env from a Victron .env file.

Never prints MQTT_PASSWORD. Loopback / placeholder hosts are replaced with the
Pi 4 broker address (Theengs on the Pi 5 cannot use 127.0.0.1).
"""
from __future__ import annotations

import argparse
import stat
import sys
from pathlib import Path

PLACEHOLDER_HOSTS = {"", "localhost", "127.0.0.1", "192.168.0.XX"}


def parse_dotenv(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        data[key.strip()] = val.strip().strip('"').strip("'")
    return data


def effective_mqtt_host(host: str, fallback: str) -> str:
    h = (host or "").strip()
    if h in PLACEHOLDER_HOSTS:
        if not fallback:
            raise ValueError("MQTT_HOST is loopback/placeholder and no fallback was given")
        return fallback
    return h


def mqtt_env_body(data: dict[str, str], fallback_host: str) -> str:
    user = data.get("MQTT_USERNAME") or data.get("MQTT_USER") or ""
    password = data.get("MQTT_PASSWORD") or ""
    port = data.get("MQTT_PORT") or "1883"
    if not user or not password:
        raise ValueError("MQTT_USER/MQTT_PASSWORD missing")
    host = effective_mqtt_host(data.get("MQTT_HOST") or "", fallback_host)
    return (
        f"MQTT_HOST={host}\n"
        f"MQTT_PORT={port}\n"
        f"MQTT_USERNAME={user}\n"
        f"MQTT_PASSWORD={password}\n"
    )


def write_mqtt_env(src: Path, dest: Path, fallback_host: str) -> str:
    data = parse_dotenv(src.read_text(encoding="utf-8", errors="replace"))
    body = mqtt_env_body(data, fallback_host)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(body, encoding="utf-8")
    dest.chmod(stat.S_IRUSR | stat.S_IWUSR)
    host_line = next(line for line in body.splitlines() if line.startswith("MQTT_HOST="))
    user_line = next(line for line in body.splitlines() if line.startswith("MQTT_USERNAME="))
    port_line = next(line for line in body.splitlines() if line.startswith("MQTT_PORT="))
    return f"wrote {dest} ({host_line} {user_line} {port_line})"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path, help="Victron .env path")
    parser.add_argument("dest", type=Path, help="Theengs mqtt.env output path")
    parser.add_argument(
        "fallback_host",
        nargs="?",
        default="192.168.0.223",
        help="Broker IP if MQTT_HOST is localhost/placeholder (default: 192.168.0.223)",
    )
    args = parser.parse_args(argv)
    if not args.src.is_file():
        print(f"no .env at {args.src}", file=sys.stderr)
        return 1
    try:
        msg = write_mqtt_env(args.src, args.dest, args.fallback_host)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
