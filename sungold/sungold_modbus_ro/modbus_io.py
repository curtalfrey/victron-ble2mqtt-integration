"""Read-only Modbus RTU client with per-register skip tracking."""

from __future__ import annotations

import json
import math
import time
from typing import TYPE_CHECKING

import minimalmodbus

from .registers import VALUE_FN, EntityDef

if TYPE_CHECKING:
    from .config import Settings

_MODBUS_FAILURE_THRESHOLD = 20


class ReadOnlyModbusClient:
    """SRNE-class inverter reader — function 03 only; never writes."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._failures = 0
        self._register_failures: dict[int, int] = {}
        self._register_skip_time: dict[int, float] = {}
        self._skipped_logged: set[int] = set()
        self._instr = minimalmodbus.Instrument(settings.modbus_device, settings.modbus_address)
        self._instr.serial.baudrate = settings.modbus_baudrate
        self._instr.serial.timeout = settings.modbus_timeout
        self._load_skip_state()

    def _load_skip_state(self) -> None:
        try:
            with open(self._settings.skip_state_file, encoding="utf-8") as fh:
                data = json.load(fh)
            for hex_key, ts in data.items():
                self._register_skip_time[int(hex_key, 16)] = float(ts)
            if self._register_skip_time:
                print(f"Loaded {len(self._register_skip_time)} skipped registers from skip state")
        except FileNotFoundError:
            pass
        except OSError as exc:
            print(f"Could not load register skip state: {exc}")

    def _save_skip_state(self) -> None:
        try:
            with open(self._settings.skip_state_file, "w", encoding="utf-8") as fh:
                json.dump({f"0x{r:04X}": ts for r, ts in self._register_skip_time.items()}, fh, indent=2)
        except OSError as exc:
            print(f"Could not save register skip state: {exc}")

    def is_register_available(self, register: int) -> bool:
        skip_time = self._register_skip_time.get(register)
        if skip_time is None:
            return True
        if time.time() - skip_time >= self._settings.modbus_skip_retry_interval:
            self._register_skip_time.pop(register, None)
            self._register_failures.pop(register, None)
            self._skipped_logged.discard(register)
            self._save_skip_state()
            print(f"Modbus: retrying register 0x{register:04X}")
            return True
        return False

    def _record_result(self, success: bool, register: int = 0) -> None:
        if success:
            self._failures = 0
            if register:
                self._register_failures.pop(register, None)
            return

        self._failures += 1
        if not register:
            return

        count = self._register_failures.get(register, 0) + 1
        self._register_failures[register] = count
        if count >= self._settings.modbus_skip_threshold and register not in self._register_skip_time:
            self._register_skip_time[register] = time.time()
            if register not in self._skipped_logged:
                print(f"Modbus: skipping register 0x{register:04X} after {count} failures")
                self._skipped_logged.add(register)
            self._save_skip_state()

    def check_reconnect(self) -> None:
        if self._failures < _MODBUS_FAILURE_THRESHOLD:
            return
        print(f"Modbus: {self._failures} consecutive failures — reopening serial port")
        try:
            self._instr.serial.close()
        except OSError:
            pass
        try:
            self._instr = minimalmodbus.Instrument(
                self._settings.modbus_device, self._settings.modbus_address
            )
            self._instr.serial.baudrate = self._settings.modbus_baudrate
            self._instr.serial.timeout = self._settings.modbus_timeout
            self._failures = 0
            self._register_failures.clear()
            self._register_skip_time.clear()
            self._skipped_logged.clear()
            self._save_skip_state()
            print("Modbus serial port reopened successfully")
        except OSError as exc:
            print(f"Modbus reconnect failed: {exc}")
            self._failures = _MODBUS_FAILURE_THRESHOLD

    @staticmethod
    def _format_scaled(value: float, scale: float, integer: bool) -> str:
        if integer or scale == 1.0:
            return str(int(value))
        decimals = max(0, round(-math.log10(scale))) if scale else 0
        return f"{value:.{decimals}f}"

    def read_entity(self, entity: EntityDef) -> str | None:  # noqa: PLR0911
        register = entity.register
        if not self.is_register_available(register):
            return None

        try:
            if entity.value_fn:
                raw = self._instr.read_register(register)
                self._record_result(True, register)
                fn = VALUE_FN.get(entity.value_fn)
                if fn is None:
                    return str(raw)
                return fn(raw)

            raw = self._instr.read_register(register, signed=entity.signed)
            if entity.clamp_zero and raw < 0:
                raw = 0
            if entity.invert:
                raw = -raw

            self._record_result(True, register)

            if entity.lookup is not None:
                return entity.lookup.get(raw, str(raw))

            if entity.format_hex:
                return f"0x{int(raw):x}"

            scaled = raw * entity.scale
            return self._format_scaled(scaled, entity.scale, entity.integer)
        except OSError as exc:
            self._record_result(False, register)
            print(f"Modbus read 0x{register:04X} ({entity.key}) failed: {exc}")
            return None
        except minimalmodbus.NoResponseError:
            self._record_result(False, register)
            return None
        except minimalmodbus.InvalidResponseError:
            self._record_result(False, register)
            return None
