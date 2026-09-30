#!/usr/bin/env python3
"""Check a development target before any hardware access. Never opens a port."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def check_target(devices, mac, chip, branch):
    mac = mac.upper()
    if not re.fullmatch(r"(?:[0-9A-F]{2}:){5}[0-9A-F]{2}", mac):
        raise ValueError("Supply the full MAC, with colons; port names and suffixes are not identities")
    matches = [device for device in devices if device.get("mac") == mac]
    if len(matches) != 1:
        raise ValueError("Unknown or ambiguous MAC; no development deployment is authorized")
    device = matches[0]
    if device.get("role") != "development":
        raise ValueError("Production/protected device: development flashing is forbidden")
    if chip != device.get("chip"):
        raise ValueError("Wrong silicon for this device")
    if branch != device.get("branch"):
        raise ValueError("Wrong branch for this device; switch to " + device["branch"])
    return device


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac", required=True)
    parser.add_argument("--chip", required=True, choices=("esp32s3", "esp32p4"))
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    branch = subprocess.run(
        ["git", "-C", str(here), "symbolic-ref", "--quiet", "--short", "HEAD"],
        check=False, capture_output=True, text=True,
    ).stdout.strip()
    try:
        registry = json.loads((here / "devices.json").read_text())
        if registry.get("schema") != 1:
            raise ValueError("Unsupported device registry schema")
        device = check_target(registry["devices"], args.mac, args.chip, branch)
    except (ValueError, KeyError, OSError) as error:
        print("Refused: " + str(error), file=sys.stderr)
        return 1
    print(f"Allowed development target: {device['mac']} ({device['chip']}) on {branch}")
    print("Before writing, verify the connected bootloader reports this exact MAC and chip.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
