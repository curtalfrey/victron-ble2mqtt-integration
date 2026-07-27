"""
CLI for usage (override)
Minimal scaffold so local CLI commands work without depending on installed package internals.
"""

import sys

from cli_base.autodiscover import import_all_files
from cli_base.cli_tools.version_info import print_version
from tyro.extras import SubcommandApp

import victron_ble2mqtt

# Create the Tyro Subcommand application object
app = SubcommandApp()

# Auto-register all CLI commands found in this package (including our override)
import_all_files(package=__package__, init_file=__file__)


@app.command
def version():
    """Print version and exit"""
    print_version(victron_ble2mqtt)
    sys.exit(0)


def main():
    print_version(victron_ble2mqtt)
    app.cli(
        prog="./cli.py",
        description="victron-ble2mqtt (override CLI)",
        use_underscores=False,  # use hyphens instead of underscores
        sort_subcommands=True,
    )
