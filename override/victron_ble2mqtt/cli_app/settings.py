from victron_ble2mqtt.user_settings import UserSettings


def get_settings() -> UserSettings:
    """Return UserSettings from Python file (no TOML)."""
    return UserSettings()
