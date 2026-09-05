import pytest

from override.victron_ble2mqtt.mqtt import calc_midpoint_shift, calc_midpoint_shift_percent


def test_midpoint_helpers():
    assert calc_midpoint_shift(100, 50) == 0.0
    assert round(calc_midpoint_shift(26.7, 13.2), 3) == 0.15
    assert calc_midpoint_shift_percent(100, 50) == 0.0
    assert round(calc_midpoint_shift_percent(26.7, 13.2), 3) == 1.124
    assert calc_midpoint_shift_percent(100, 51) == 2.0


def test_no_per_device_decimal_scaling_present():
    # Ensure we didn't sneak in a per-name correction (like dividing by 100 for 'Battery 1')
    import inspect
    import override.victron_ble2mqtt.victron_ble_utils as u

    src = inspect.getsource(u.GenericDevice.parse)
    assert '/ 100' not in src and 'divide' not in src.lower()