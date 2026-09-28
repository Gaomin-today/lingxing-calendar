#!/usr/bin/env python3
"""Regenerate synthetic numeric Heluo fixtures from the user-owned reference skill.

No skill text, modern interpretation, or real birth profile is copied. Pass both
paths explicitly; the app never requires Python or this private reference folder.
Requires lunar_python 1.4.8 in --dependency-path. Boundary fixes are declared below
and separately tested in Swift rather than treated as upstream behavior.
"""
import argparse
from datetime import datetime, timedelta
import hashlib
import importlib.metadata
import json
from pathlib import Path
import random
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--skill-path', required=True, type=Path)
parser.add_argument('--dependency-path', required=True, type=Path)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'Tests/Fixtures/heluo-reference.json')
args = parser.parse_args()
sys.dont_write_bytecode = True
sys.path[:0] = [str(args.skill_path), str(args.dependency_path)]
assert importlib.metadata.version('lunar_python') == '1.4.8'
from lunar_python import Solar
from bazi_chart import heluogua as h
from bazi_chart.rules import HEXAGRAMS


def flow_year(dt):
    start = h._month_jieqi_datetimes(dt.year)[0]
    return dt.year if dt >= start else dt.year - 1


def values(birth, gender, query, sect):
    lunar = Solar.fromYmdHms(birth.year, birth.month, birth.day, birth.hour, birth.minute, 0).getLunar()
    eight = lunar.getEightChar()
    eight.setSect(sect)
    texts = [eight.getYear(), eight.getMonth(), eight.getDay(), eight.getTime()]
    pillars = {key: {'gan': text[0], 'zhi': text[1]} for key, text in zip(('year', 'month', 'day', 'time'), texts)}
    upper, lower, tian, di = h._xiantian_trigrams(pillars, birth.year, gender)
    first_lines = h.TRIGRAM_LINES[lower] + h.TRIGRAM_LINES[upper]
    first = h._hexagram_from_lines(first_lines)
    yuan = h._yuan_tang_position(first_lines, pillars['time']['zhi'])
    second_lines = h._houtian_lines(first, first_lines, yuan, lunar.getMonth())
    second = h._hexagram_from_lines(second_lines)
    by, qy = flow_year(birth), flow_year(query)
    first_schedule = h._segment_schedule('先天', first_lines, yuan, by, 1)
    schedule = first_schedule + h._segment_schedule('后天', second_lines, yuan, by, first_schedule[-1].end_age + 1)
    age = qy - by + 1
    segment = next(s for s in schedule if s.start_age <= age <= s.end_age)
    annual, year_line, year_lines = h._current_year_hexagram(first_lines if segment.phase == '先天' else second_lines, segment, qy)
    # Keep the original month-line formula, replace its incorrect same-year 小寒.
    bounds = h._month_jieqi_datetimes(qy)
    bounds[11] = h._month_jieqi_datetimes(qy + 1)[11]
    months, _ = h._month_hexagram_schedule(qy, annual['name'], year_lines, year_line, query)
    month_index = next(i for i in range(12) if bounds[i] <= query < bounds[i + 1])
    month = months[month_index]
    month_lines = h.TRIGRAM_LINES[month['lower']] + h.TRIGRAM_LINES[month['upper']]
    offset = (query.date() - bounds[month_index].date()).days
    trigger = ((month['current_line']['position'] + offset // 6) % 6) + 1
    day = h._hexagram_from_lines(h._toggle(month_lines, trigger))
    return dict(
        birth=birth.isoformat(timespec='minutes'), gender='male' if gender == '男' else 'female',
        query=query.isoformat(timespec='minutes') + '+08:00', dayBoundary='midnight' if sect == 2 else 'ziHour23',
        natalPillars=texts, tianNumber=tian, diNumber=di, xianTian=first['number'], houTian=second['number'],
        yuanTang=yuan, year=annual['number'], yearLine=year_line, month=month['number'],
        monthLine=month['current_line']['position'], monthIndex=month_index + 1,
        day=day['number'], dayLine=offset % 6 + 1, dayIndex=offset, triggerLine=trigger,
        nominalAge=age, firstPhaseEndAge=first_schedule[-1].end_age, lastAge=schedule[-1].end_age,
        phase=segment.phase,
    )

rng = random.Random(601942)
cases = []
# Synthetic dates cover all three source-script yuan bands, both genders, late 子,
# birth before Li-Chun, reference special gua handling, and multiple life phases.
for index in range(160):
    birth_year = rng.choice([1901, 1910, 1923, 1924, 1960, 1983, 1984, 1990, 2000, 2026, 2044])
    birth = datetime(birth_year, rng.randint(1, 12), rng.randint(1, 28), rng.choice([0, 1, 5, 9, 12, 15, 18, 21, 23]), rng.choice([0, 30, 59]))
    query_year = min(birth_year + rng.randint(1, 72), 2099)
    query = datetime(query_year, rng.randint(1, 12), rng.randint(1, 28), 12)
    cases.append(values(birth, '男' if index % 2 == 0 else '女', query, 1 if index % 3 == 0 else 2))
# All three special-life hexagrams with the sixth yuan-tang line, odd/even lunar months.
for birth_text, gender in [('2000-01-02', '女'), ('2000-01-17', '男'), ('2000-02-16', '男'),
                          ('2000-03-30', '男'), ('2000-04-26', '女'), ('2000-09-05', '男')]:
    cases.append(values(datetime.fromisoformat(birth_text + 'T18:00'), gender, datetime(2026, 9, 17, 12), 2))
# Explicit same-source nominal year vs Jan-boundary regression cases.
for text in ['2026-01-01T12:00', '2026-01-06T12:00', '2026-02-04T04:01', '2026-02-04T04:03', '2026-12-09T12:00', '2027-01-04T12:00', '2027-01-06T12:00']:
    cases.append(values(datetime(1990, 6, 15, 9, 30), '男', datetime.fromisoformat(text), 2))
result = {
    'schemaVersion': 1, 'dependency': 'lunar_python==1.4.8',
    'sourceSHA256': hashlib.sha256((args.skill_path / 'bazi_chart/heluogua.py').read_bytes()).hexdigest(),
    'policy': 'Original private-reference numeric helper functions, synthetic fixed UTC+08:00 civil births only. Birth and query year labels normalized to Li-Chun; month 12 starts at NEXT January Xiao-Han; day offsets use the actual selected local civil date. Source modern texts deliberately excluded.',
    'hexagrams': [dict(number=number, name=name, lines=h.TRIGRAM_LINES[lower] + h.TRIGRAM_LINES[upper])
                  for (upper, lower), (number, name) in sorted(HEXAGRAMS.items(), key=lambda kv: kv[1][0])],
    'cases': cases,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(f'{len(cases)} synthetic cases; {len(result["hexagrams"])} public-domain hexagram mappings; {args.output}')
