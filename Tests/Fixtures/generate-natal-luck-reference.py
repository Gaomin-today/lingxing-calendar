#!/usr/bin/env python3
"""Development-only: requires the same isolated lunar_python 1.4.8 setup as
scripts/verify-reference-skills.py. Does not modify the original local skills.
Actual bazi engine provides the detail facts; supplemental EightChar.getYun
explicitly uses sect 2, since that engine's default luck conversion is sect 1.
"""
from pathlib import Path
import hashlib
import importlib.metadata
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path[:0] = [str(ROOT / "build/python-reference/site-packages"), str(ROOT / "LocalReferenceSkills/bazi-pro")]
assert importlib.metadata.version("lunar_python") == "1.4.8"
from lunar_python import Solar
from bazi_chart.engine import build_chart

cases = []
for date_text, time_text, genders in (
    ("1988-02-15", "23:30", ("男", "女")),
    ("2005-12-23", "08:37", ("男", "女")),
    ("1990-03-08", "12:00", ("男", "女")),
    ("2026-02-04", "04:01", ("男",)),
    ("2026-02-04", "04:03", ("男",)),
):
    for gender in genders:
        actual = build_chart(
            calendar="solar", date_text=date_text, time_text=time_text, gender=gender,
            birthplace="synthetic UTC+8 fixture", latitude=0.0, longitude=120.0, timezone=8.0,
            current_date="2026-09-17", daylight_saving_hours=0.0,
            time_policy="standard", flow_years=0, include_flow_days=False,
        )
        y, m, d = map(int, date_text.split("-"))
        h, minute = map(int, time_text.split(":"))
        eight = Solar.fromYmdHms(y, m, d, h, minute, 0).getLunar().getEightChar()
        eight.setSect(1)  # day-column policy; independent from Yun's sect below
        yun = eight.getYun(1 if gender == "男" else 0, 2)
        details = []
        for key in ("year", "month", "day", "time"):
            p = actual["pillars"][key]
            details.append({
                "id": "hour" if key == "time" else key,
                "pillar": p["gan_zhi"], "tenGod": p["ten_god_gan"],
                "stemElement": p["gan_element"], "branchElement": p["zhi_element"],
                "hiddenStems": [{"stem": s["gan"], "element": s["element"], "tenGod": s["ten_god"]} for s in p["hidden_gan"]],
                "naYin": p["na_yin"], "dayMasterStage": p["xing_yun"],
                "selfStage": p["self_changsheng"], "xunKong": "".join(p["xun_kong"]),
            })
        cases.append({
            "id": f"{date_text}-{time_text}-{gender}",
            "date": date_text, "time": time_text, "gender": "male" if gender == "男" else "female",
            "dayBoundary": "ziHour23", "timeZone": "Asia/Shanghai", "details": details,
            "direction": "forward" if yun.isForward() else "backward",
            "offset": [yun.getStartYear(), yun.getStartMonth(), yun.getStartDay(), yun.getStartHour()],
            "startAt": yun.getStartSolar().toYmdHms().replace(" ", "T") + "+08:00",
            "firstThreePillars": [dy.getGanZhi() for dy in yun.getDaYun(4)[1:]],
            "actualSkillSect1StartForComparison": actual["luck"]["start"]["solar"]["text"],
        })

sources = ("LocalReferenceSkills/bazi-pro/bazi_chart/engine.py", "LocalReferenceSkills/bazi-pro/bazi_chart/rules.py")
result = {
    "schemaVersion": 1,
    "dependency": "lunar_python==1.4.8",
    "sourcesSHA256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
    "policies": {
        "details": "Actual bazi_chart.engine.build_chart, standard civil UTC+08:00, no DST, day sect 1.",
        "luck": "Supplemental lunar_python.EightChar.getYun(gender, 2); the actual skill uses luck sect 1 and therefore is NOT the expected start-time policy.",
        "intervals": "Only start and first three pillars are borrowed; native half-open exact ten-year boundaries replace the skill's end-minus-one-day logic.",
        "synthetic": "All records are test inputs, not user birth information. Gender is an explicit traditional rule input.",
    },
    "cases": cases,
}
destination = ROOT / "Tests/Fixtures/natal-luck-reference.json"
destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for item in cases:
    print(item["id"], item["direction"], item["offset"], item["startAt"], " ".join(item["firstThreePillars"]))
