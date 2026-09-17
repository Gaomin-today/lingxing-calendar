#!/usr/bin/env python3
"""Reproduce synthetic four-pillar fixtures using the user's local skill engines.

Requires Python >= 3.10. Install the pinned dependency into an isolated directory:
  python3 -m pip install --no-deps --target build/python-reference/site-packages lunar_python==1.4.8
Run this script normally to verify the checked-in facts, or pass --write-fixtures
to regenerate them after reviewing a reference-engine change. The local skills
are development references only; neither they nor Python ship in the Mac app.
Swift's offline reference test verifies these same facts against the native app
engine, and does not require either skill or Python to be installed.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Tests/Fixtures/reference-four-pillars.json"
DEPENDENCY = "lunar_python"
VERSION = "1.4.8"
SDIST_SHA256 = "3aa11cc73c25e70ddf0ba5bdac7398c03acc9491a3aa512a91c9642973b669d6"
PILLAR_KEYS = ("year", "month", "day", "time")


def source_hash(relative_path: str) -> str:
    return hashlib.sha256((ROOT / relative_path).read_bytes()).hexdigest()


def record(identifier: str, local: str, source: str, boundary: str, pillars: dict, **metadata) -> dict:
    return {
        "id": identifier,
        "instant": local.replace(" ", "T") + "+08:00",
        "timeZone": "Asia/Shanghai",
        "dayBoundary": boundary,
        "referenceEngine": source,
        "referencePolicy": metadata,
        "pillars": pillars,
    }


def generate() -> dict:
    # Actual skill engines are deliberately used for the main cases, not merely
    # a replacement call to their shared dependency. Disable bytecode writes so
    # verification leaves the user-provided originals untouched.
    from wannianli.engine import build_calendar_day
    from bazi_chart.engine import build_chart
    from lunar_python import Solar

    cases = []
    for identifier, local in (
        ("late-zi-before", "1988-02-15 22:59:00"),
        ("late-zi-after", "1988-02-15 23:30:00"),
        ("next-midnight", "1988-02-16 00:00:00"),
        ("lichun-before", "2026-02-04 04:02:06"),
        ("lichun-after", "2026-02-04 04:02:10"),
        ("ordinary-day", "2026-09-17 12:00:00"),
    ):
        date_text, time_text = local.split()
        result = build_calendar_day(date_text=date_text, time_text=time_text, timezone="Asia/Shanghai")
        cases.append(record(
            identifier, local, "wannianli.engine.build_calendar_day", "ziHour23",
            {key: result["pillars"][key]["gan_zhi"] for key in PILLAR_KEYS},
            sect=1, timePolicy="civil UTC+08:00", timezoneArgument="echo only; no IANA conversion",
        ))

    bazi = build_chart(
        calendar="solar", date_text="1988-02-15", time_text="23:30", gender="男",
        birthplace="synthetic UTC+8 fixture", latitude=0.0, longitude=120.0, timezone=8.0,
        current_date="2026-09-17", daylight_saving_hours=0.0,
        time_policy="standard", flow_years=0, include_flow_days=False,
    )
    cases.append(record(
        "bazi-standard-late-zi", "1988-02-15 23:30:00", "bazi_chart.engine.build_chart", "ziHour23",
        {key: bazi["pillars"][key]["gan_zhi"] for key in PILLAR_KEYS},
        sect=1, timePolicy=bazi["input"]["time_policy"], chartSolar=bazi["chart_solar"]["text"],
        dstHours=0, gender="synthetic fixture only; not a user birth record",
    ))

    # Supplemental sect 2 explicitly verifies the app's different default day
    # boundary; neither actual skill exposes this configuration in its engine.
    eight = Solar.fromYmdHms(1988, 2, 15, 23, 30, 0).getLunar().getEightChar()
    eight.setSect(2)
    cases.append(record(
        "midnight-policy-late-zi", "1988-02-15 23:30:00", "lunar_python.EightChar", "midnight",
        dict(zip(PILLAR_KEYS, (eight.getYear(), eight.getMonth(), eight.getDay(), eight.getTime()))),
        sect=2, timePolicy="civil UTC+08:00; late-zi hour stem uses the following day",
    ))

    sources = [
        "LocalReferenceSkills/wannianli-pro/pyproject.toml",
        "LocalReferenceSkills/wannianli-pro/wannianli/engine.py",
        "LocalReferenceSkills/wannianli-pro/scripts/calendar_query.py",
        "LocalReferenceSkills/bazi-pro/pyproject.toml",
        "LocalReferenceSkills/bazi-pro/bazi_chart/engine.py",
    ]
    return {
        "schemaVersion": 1,
        "dependency": {"name": DEPENDENCY, "version": VERSION, "pypiSdistSHA256": SDIST_SHA256},
        "sourceSHA256": {path: source_hash(path) for path in sources},
        "notes": [
            "All inputs are synthetic regression cases, not personal birth records.",
            "Six cases execute the real wannianli engine; one executes the real bazi engine in standard time.",
            "The supplemental lunar_python sect 2 case separately verifies the app's midnight default.",
            "Cases use UTC+08:00 dates without historical DST; wannianli's timezone argument does not convert instants.",
            "Python reports 2026 Lichun at 04:02:08 rounded to seconds; native Swift retains 04:02:08.404. Cases bracket it by two seconds.",
            "calendar_query.py uses non-Exact year/month/day methods and is not the same four-pillar policy as wannianli.engine.",
            "The Python and Swift libraries share the ShouXing algorithm family; agreement is a compatibility check, not independent astronomical accuracy proof.",
            "User-provided skills have no included redistribution license and are not bundled into the app or repository.",
        ],
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dependencies", type=Path, default=ROOT / "build/python-reference/site-packages")
    parser.add_argument("--write-fixtures", action="store_true", help="Update the committed expected facts after review")
    args = parser.parse_args()
    if sys.version_info < (3, 10):
        parser.error("Python >= 3.10 is required by the local reference skills")
    sys.dont_write_bytecode = True
    dependency_path = args.dependencies.resolve()
    if not dependency_path.is_dir():
        parser.error(f"Missing isolated dependency directory: {dependency_path}; see this script's setup instructions")
    sys.path[:0] = [str(dependency_path), str(ROOT / "LocalReferenceSkills/wannianli-pro"), str(ROOT / "LocalReferenceSkills/bazi-pro")]
    distribution = importlib.metadata.distribution(DEPENDENCY)
    if distribution.version != VERSION or not Path(distribution.locate_file("")).resolve().is_relative_to(dependency_path):
        parser.error(f"Expected isolated {DEPENDENCY}=={VERSION}, refusing another version or global installation")
    generated = generate()
    if args.write_fixtures:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(json.dumps(generated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {FIXTURE.relative_to(ROOT)}")
    elif generated != json.loads(FIXTURE.read_text(encoding="utf-8")):
        print("Reference facts or source hashes changed. Review before regenerating fixtures.", file=sys.stderr)
        return 1
    for case in generated["cases"]:
        print(f"OK {case['id']}: {' '.join(case['pillars'][key] for key in PILLAR_KEYS)} ({case['dayBoundary']})")
    print("8 Python reference cases verified. Run scripts/test.sh to compare the same fixtures with native Swift.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
