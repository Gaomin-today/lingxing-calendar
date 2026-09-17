#!/usr/bin/env python3
"""Verify synthetic almanac facts against the user's real wannianli engine.

Uses the isolated, fixed lunar_python 1.4.8 installation. Original skills are
read-only; bytecode generation is disabled. The Swift app needs neither Python
nor these development references. Default mode verifies; --write regenerates.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("almanac-reference.json")
DATES = ("1901-01-01", "1988-02-15", "2025-08-12", "2026-02-04", "2026-09-17", "2099-12-31")
HOURS = (0, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23)


def generate() -> dict:
    from wannianli.engine import build_calendar_day

    cases = []
    for date in DATES:
        ref = build_calendar_day(date_text=date, time_text="12:00")
        result = {"date": date, "day": ref["huangli"]["day"],
                  "positions": ref["huangli"]["positions"]["day"], "hours": []}
        result["day"]["luck"] = ref["huangli"]["extended"]["day_tian_shen_luck"]
        result["stars"] = {k: ref["flying_star"][k]["number"] for k in ("year", "month", "day")}
        for hour in HOURS:
            timed = build_calendar_day(date_text=date, time_text=f"{hour:02d}:00")
            item = dict(timed["huangli"]["time"])
            item.update(hour=hour, ganZhi=timed["pillars"]["time"]["gan_zhi"],
                        star=timed["flying_star"]["time"]["number"],
                        positions=timed["huangli"]["positions"]["time"])
            result["hours"].append(item)
        cases.append(result)
    source = ROOT / "LocalReferenceSkills/wannianli-pro/wannianli/engine.py"
    return {"source": "wannianli.engine.build_calendar_day",
            "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "dependency": "lunar_python==1.4.8",
            "timezone": "Asia/Shanghai (civil UTC+08 reference fields; no IANA conversion in Python engine)",
            "cases": cases}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="replace the fixture after reviewing engine changes")
    args = parser.parse_args()
    sys.dont_write_bytecode = True
    sys.path[:0] = [str(ROOT / "build/python-reference/site-packages"),
                   str(ROOT / "LocalReferenceSkills/wannianli-pro")]
    if importlib.metadata.version("lunar_python") != "1.4.8":
        raise SystemExit("Expected the isolated lunar_python==1.4.8 installation")
    expected = generate()
    if args.write:
        FIXTURE.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Wrote 6 synthetic dates × 13 hour intervals")
    elif json.loads(FIXTURE.read_text(encoding="utf-8")) != expected:
        raise SystemExit("FAIL: almanac reference changed; review source/data differences before regenerating")
    else:
        print("PASS: 6 synthetic dates × 13 hour intervals match actual wannianli engine (lunar_python 1.4.8)")


if __name__ == "__main__":
    main()
