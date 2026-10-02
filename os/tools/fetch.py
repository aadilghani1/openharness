#!/usr/bin/env python3
"""Fetch immutable, checksum-verified Harness inputs. No install scripts execute."""
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.request


def fetch(entry, destination):
    destination = Path(destination)
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == entry['sha256']:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix('.download')
    try:
        digest = hashlib.sha256()
        with urllib.request.urlopen(entry['url'], timeout=90) as response, temporary.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != entry['sha256']:
            raise ValueError(f"checksum mismatch: {destination.name}")
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    lock = json.loads((root / 'lock.json').read_text())
    target = Path(sys.argv[1])
    for key, name in [('hn', 'hn'), ('cli', 'cli.mjs'), ('notify', 'notify.mjs')]:
        fetch(lock['artifacts'][key], target / name)
    (target / 'hn').chmod(0o755)
