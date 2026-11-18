#!/usr/bin/env python3
"""Emit every possible bundled packet card name for PacketCompatibilityTest.

Usage: python3 RulesBridge/tests/packet-manifest.py > RulesBridge/build/packet-compatibility-input.json
Run from anywhere; includes positive-probability Jump In variants, not a random draw.
"""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "CardService"
packets = []
for path in sorted((root / "JumpStart").rglob("*.txt")):
    names = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        match = re.fullmatch(r"\s*\d+\s+(.+?)(?:\s+\([^)]+\)(?:\s+\S+)?)?\s*", line)
        if match:
            names.append(match[1])
    if not names:
        raise ValueError(f"No cards found in {path}")
    packets.append(dict(source="JumpStart", set=path.parent.name, packet=path.stem, cards=sorted(set(names))))
for packet in json.loads((root / "JumpIn" / "packets.json").read_text()):
    names = list(packet["fixedCards"])
    for slot in packet["randomSlots"]:
        names.extend(option["name"] for option in slot if option["probability"] > 0)
    packets.append(dict(source="Jump In", set=packet["setCode"], packet=packet["name"], cards=sorted(set(names))))
print(json.dumps(packets, ensure_ascii=False, indent=2))
