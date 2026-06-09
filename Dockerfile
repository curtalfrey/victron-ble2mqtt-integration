FROM python:3.11-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireless-tools bluez libglib2.0-0 dbus libbluetooth3 \
 && rm -rf /var/lib/apt/lists/*

# Hub wheels (sync via scripts/sync-victron-wheels-from-hub.sh); empty dir = PyPI-only build.
ARG PIP_OFFLINE=0
COPY wheels /tmp/wheels
COPY requirements.lock /tmp/requirements.txt

RUN set -eu; \
    if [ "${PIP_OFFLINE}" = "1" ]; then \
      pip install --no-cache-dir --no-index --find-links=/tmp/wheels -r /tmp/requirements.txt; \
    else \
      pip install --no-cache-dir --find-links=/tmp/wheels -r /tmp/requirements.txt; \
    fi && rm -rf /tmp/wheels /tmp/requirements.txt

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/override:/app:/work
WORKDIR /app
COPY victron_ble2mqtt /app/victron_ble2mqtt
COPY override/victron_ble2mqtt /app/override/victron_ble2mqtt
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
# Liveness: the publish loop touches HEARTBEAT_FILE after each successful
# system-info MQTT publish (override/victron_ble2mqtt/__main__.py).
# Stale heartbeat (> 20x poll interval + 60s margin) => unhealthy => autoheal restart.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python -c "import os,sys,time; p=os.environ.get('HEARTBEAT_FILE','/tmp/victron_ble2mqtt.heartbeat'); max_age=20*float(os.environ.get('SYSTEM_POLL_THROTTLE_SEC') or 3)+60; m=os.path.getmtime(p) if os.path.exists(p) else 0; sys.exit(0 if time.time()-m<=max_age else 1)" || exit 1
CMD ["docker-entrypoint.sh"]
