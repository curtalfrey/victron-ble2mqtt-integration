from importlib import metadata

try:
    __version__ = metadata.version("victron-ble2mqtt")
except Exception:
    __version__ = "0.0.0-local"
__all__ = ["__version__"]
