"""Curated read-only SRNE holding registers for SPH302480A (single-phase, one MPPT).

Register addresses and scaling follow timbit123/srne-modbus (Apache-2.0 patterns).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

CHARGING_STATES: dict[int, str] = {
    0: "Not Charging",
    1: "Quick Charge",
    2: "Constant Voltage Charge",
    4: "Float Charge",
    6: "Battery Activation",
    8: "Fully Charged",
}

MACHINE_STATES: dict[int, str] = {
    0: "Initialization",
    1: "Standby state",
    2: "AC power operation",
    3: "Inverter operation",
}

FAIL_CODES: dict[int, str] = {
    0: "No reported error",
    1: "Battery undervoltage alarm",
    2: "Battery discharge average current overcurrent (software protection)",
    3: "Battery not-connected alarm",
    4: "Battery undervoltage stop discharge alarm",
    5: "Battery overcurrent (hardware protection)",
    6: "Charging overvoltage protection",
    7: "Bus overvoltage (hardware protection)",
    8: "Bus overvoltage (software protection)",
    9: "PV overvoltage protection",
    10: "AFCI Fault/Boost overcurrent (software protection)",
    11: "Boost overcurrent (hardware protection",
    13: "Bypass overload protection",
    14: "Inverter overload protection",
    15: "Inverter overcurrent hardware protection",
    17: "Inverter short-circuit protection",
    19: "Buck heat sink over temperature protection",
    20: "Inverter AC output over-temperature protection",
    21: "Fan blockage or failure fault",
}


@dataclass(frozen=True)
class EntityDef:
    key: str
    name: str
    register: int
    topic_type: str = "sensor"
    scale: float = 1.0
    signed: bool = False
    integer: bool = False
    lookup: dict[int, str] | None = None
    device_class: str | None = None
    state_class: str | None = None
    unit: str | None = None
    icon: str | None = None
    entity_category: str | None = None
    clamp_zero: bool = False
    format_hex: bool = False
    invert: bool = False
    value_fn: str | None = None  # "failcode" for special decode


# SPH302480A defaults: single-phase 120 V, one MPPT channel.
CURATED_ENTITIES: tuple[EntityDef, ...] = (
    # PV (one MPPT)
    EntityDef("pv1/voltage", "PV Voltage", 0x0107, scale=0.1, device_class="voltage", state_class="measurement", unit="V", icon="mdi:solar-power"),
    EntityDef("pv1/current", "PV Current", 0x0108, scale=0.1, device_class="current", state_class="measurement", unit="A", icon="mdi:solar-power"),
    EntityDef("pv1/power", "PV Power", 0x0109, integer=True, device_class="power", state_class="measurement", unit="W", icon="mdi:solar-power"),
    EntityDef("pv/total_power", "PV Total Power", 0x010A, integer=True, device_class="power", state_class="measurement", unit="W", icon="mdi:solar-power"),
    # Battery
    EntityDef("battery/soc", "Battery SOC", 0x0100, integer=True, device_class="battery", state_class="measurement", unit="%", icon="mdi:battery"),
    EntityDef("battery/voltage", "Battery Voltage", 0x0101, scale=0.1, device_class="voltage", state_class="measurement", unit="V", icon="mdi:current-dc"),
    EntityDef("battery/current", "Battery Current", 0x0102, scale=0.1, signed=True, device_class="current", state_class="measurement", unit="A", icon="mdi:current-dc"),
    EntityDef("battery/temperature", "Battery Temperature", 0x0103, scale=0.1, signed=True, device_class="temperature", state_class="measurement", unit="°C", icon="mdi:thermometer"),
    EntityDef("battery/charge_state", "Charge State", 0x010B, lookup=CHARGING_STATES, icon="mdi:battery-charging"),
    EntityDef("inverter/charging_power", "Charging Power", 0x010E, integer=True, device_class="power", state_class="measurement", unit="W", icon="mdi:battery-charging"),
    # Inverter status / faults
    EntityDef("inverter/state", "Inverter State", 0x0210, lookup=MACHINE_STATES, icon="mdi:information"),
    EntityDef("inverter/error_flags", "Inverter Error Flags", 0x0200, integer=True, format_hex=True, entity_category="diagnostic", icon="mdi:alert-circle"),
    EntityDef("inverter/failcode", "Fail Code", 0x0204, value_fn="failcode", entity_category="diagnostic", icon="mdi:alert-circle"),
    # Grid (phase A — single-phase unit)
    EntityDef("grid/voltage", "Grid Voltage", 0x0213, scale=0.1, device_class="voltage", state_class="measurement", unit="V", icon="mdi:transmission-tower"),
    EntityDef("grid/current", "Grid Current", 0x0214, scale=0.1, device_class="current", state_class="measurement", unit="A", icon="mdi:transmission-tower"),
    EntityDef("grid/frequency", "Grid Frequency", 0x0215, scale=0.01, device_class="frequency", state_class="measurement", unit="Hz", icon="mdi:sine-wave"),
    EntityDef("grid/power", "Grid Power", 0x023A, signed=True, integer=True, invert=True, device_class="power", state_class="measurement", unit="W", icon="mdi:transmission-tower"),
    # AC output / load
    EntityDef("inverter/voltage", "AC Output Voltage", 0x0216, scale=0.1, device_class="voltage", state_class="measurement", unit="V", icon="mdi:lightning-bolt"),
    EntityDef("inverter/frequency", "AC Output Frequency", 0x0218, scale=0.01, device_class="frequency", state_class="measurement", unit="Hz", icon="mdi:sine-wave"),
    EntityDef("load/current", "Load Current", 0x0219, scale=0.1, clamp_zero=True, device_class="current", state_class="measurement", unit="A", icon="mdi:flash"),
    EntityDef("load/power", "Load Power", 0x021B, clamp_zero=True, device_class="power", state_class="measurement", unit="W", icon="mdi:flash"),
    # Temperatures
    EntityDef("temperature/dc_dc", "Temperature DC-DC", 0x0220, scale=0.1, signed=True, device_class="temperature", state_class="measurement", unit="°C", icon="mdi:thermometer"),
    EntityDef("temperature/dc_ac", "Temperature DC-AC", 0x0221, scale=0.1, signed=True, device_class="temperature", state_class="measurement", unit="°C", icon="mdi:thermometer"),
    EntityDef("temperature/transformer", "Temperature Transformer", 0x0222, scale=0.1, signed=True, device_class="temperature", state_class="measurement", unit="°C", icon="mdi:thermometer"),
    # Binary sensors
    EntityDef("inverter/fault_active", "Fault Active", 0x0204, topic_type="binary_sensor", value_fn="fault_binary", icon="mdi:alert"),
)


def decode_failcode(raw: int) -> str:
    if raw == 0:
        return FAIL_CODES[0]
    return FAIL_CODES.get(raw, f"Unknown fault ({raw})")


def decode_fault_binary(raw: int) -> str:
    return "ON" if raw != 0 else "OFF"


VALUE_FN: dict[str, Callable[[int], str]] = {
    "failcode": decode_failcode,
    "fault_binary": decode_fault_binary,
}
