"""Configure console streams at command-line entry points."""

import sys


def configure_console() -> None:
    for stream in (sys.stdout, sys.stderr, sys.__stdout__, sys.__stderr__):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, OSError, ValueError):
            # Embedded interpreters and capture streams may not be reconfigurable.
            pass
