FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    udev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sungold_modbus_ro ./sungold_modbus_ro

ENV PYTHONUNBUFFERED=1 \
    HEARTBEAT_FILE=/tmp/sungold_modbus_ro.heartbeat \
    POLL_INTERVAL_SEC=5

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD python -c "import os,sys,time; p=os.environ.get('HEARTBEAT_FILE','/tmp/sungold_modbus_ro.heartbeat'); max_age=4*float(os.environ.get('POLL_INTERVAL_SEC') or 5)+60; m=os.path.getmtime(p) if os.path.exists(p) else 0; sys.exit(0 if time.time()-m<=max_age else 1)" || exit 1

CMD ["python", "-m", "sungold_modbus_ro"]
