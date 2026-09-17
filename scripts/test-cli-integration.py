#!/usr/bin/env python3
"""Exercise the running preview app through its shipped CLI, using synthetic data.

Build and launch 灵性日历预览.app first, then run this script. Every command
explicitly uses --preview; a successful status.preview=true check is required
before any mutation. Created records are removed in finally, including on test
failure. Completed mutation receipts remain in the preview receipt archive.
No JSON storage file, real app socket, Apple item, or notification is modified.
"""

import argparse
from datetime import datetime
import json
import pathlib
import subprocess
import sys
import uuid


class PreviewSuite:
    def __init__(self, cli):
        self.cli = str(cli)
        self.run_id = "cli-test-" + uuid.uuid4().hex[:12]
        self.safe_to_write = False
        self.created = []
        self.checks = 0
        self.date = "2026-09-20"

    def check(self, condition, label):
        if not condition:
            raise AssertionError(label)
        self.checks += 1
        print("PASS " + label, flush=True)

    def request(self, method, params=None, request_id=None, error=None):
        params = params or {}
        mutating = method.split(".")[-1] in {
            "create", "update", "delete", "save", "complete"
        }
        if mutating and not self.safe_to_write:
            raise RuntimeError("Refusing mutation before preview identity verification")
        args = [self.cli, "--preview"] + method.split(".")
        args += ["--input", "-"]
        if mutating:
            request_id = request_id or self.run_id + "-" + uuid.uuid4().hex
            args += ["--request-id", request_id]
        result = subprocess.run(
            args, input=json.dumps(params, ensure_ascii=False), text=True,
            capture_output=True, timeout=40, check=False,
        )
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise AssertionError("%s did not return JSON (exit %s)" % (method, result.returncode)) from exc
        # Record unexpected successful creates too, so a failed rejection test
        # still cleans up the synthetic record it accidentally created.
        if payload.get("ok") and mutating and (
            method.endswith(".create") or (method == "insights.save" and "id" not in params)
        ):
            record = payload.get("result", {})
            domain = "insights" if method.startswith("insights.") else method.split(".")[0]
            key = (domain, record.get("id"))
            if key[1] and key not in self.created:
                self.created.append(key)
        if error is not None:
            actual = payload.get("error", {}).get("code")
            accepted = {error} if isinstance(error, str) else set(error)
            if payload.get("ok") or actual not in accepted or result.returncode == 0:
                raise AssertionError("%s expected %s, got %s (exit %s)" % (
                    method, sorted(accepted), actual or "success", result.returncode))
            if actual.endswith("conflict"):
                self.check(result.returncode == 5, method + " conflict exit code")
            return payload
        if not payload.get("ok") or result.returncode != 0:
            problem = payload.get("error", {})
            raise AssertionError("%s failed: %s: %s (exit %s)" % (
                method, problem.get("code"), problem.get("message"), result.returncode))
        return payload

    def read(self, method, params=None):
        return self.request(method, params)["result"]

    def write(self, method, params, request_id=None):
        return self.request(method, params, request_id=request_id)["result"]

    def execute(self):
        status = self.read("status")
        self.check(status.get("preview") is True, "connected app is isolated preview")
        self.check(status.get("writesAvailable") is True, "preview mutation receipts are available")
        self.check(status.get("protocolVersion") == 1, "protocol version 1")
        self.safe_to_write = True
        capabilities = self.read("capabilities")
        self.check({"chart.show", "context.day", "tasks.show", "insights.show", "strength.show", "hexagrams.show"}.issubset(
            capabilities["readMethods"]), "capabilities expose structured reading methods")
        self.check(capabilities["appleWrites"] is False, "CLI declares local-only mutations")

        profile_input = {
            "name": "合成验收 " + self.run_id[-6:],
            "birthYear": 1990, "birthMonth": 6, "birthDay": 15,
            "birthTimeKnown": True, "birthHour": 9, "birthMinute": 30,
            "timeZoneIdentifier": "Asia/Shanghai", "dayBoundary": "midnight",
            "luckGender": "male", "strengthAssumption": "unspecified",
        }
        profile_request = self.run_id + "-profile"
        created_profile = self.write("profiles.create", profile_input, profile_request)
        profile_id = created_profile["id"]
        profile_revision = created_profile["revision"]
        replay = self.request("profiles.create", profile_input, request_id=profile_request)
        self.check(replay.get("replayed") is True and replay["result"] == created_profile,
                   "identical profile create replays exact receipt")
        self.request("profiles.create", dict(profile_input, name="不同合成参数"),
                     request_id=profile_request, error="request_id_conflict")
        profiles = self.read("profiles.list")["profiles"]
        self.check(sum(p["profile"]["id"] == profile_id for p in profiles) == 1,
                   "replayed create does not duplicate profile")
        profile = self.read("profiles.show", {"id": profile_id})
        self.check(profile["revision"] == profile_revision, "profile read has stable revision")
        chart = self.read("chart.show", {"profile": profile_id})["charts"]
        self.check(len(chart) == 1 and chart[0]["knownPillarCount"] == 4,
                   "known birth resolves four pillars")
        self.check(all(chart[0]["pillars"][p]["hiddenStems"] for p in ["year", "month", "day", "hour"]),
                   "all natal pillars include hidden stems")
        self.check(bool(chart[0]["sources"]) and bool(chart[0]["previousJie"]["date"]),
                   "chart preserves calculation sources and solar-term instants")
        luck = self.read("luck.show", {"profile": profile_id, "year": 2026})
        self.check(len(luck["luck"]["cycles"]) == 10, "luck response contains ten major cycles")
        self.check(len(luck["flowYear"]["months"]) == 12, "flow year includes twelve solar-term months")
        calendar = self.read("calendar.day", {"date": self.date})
        self.check(len(calendar["almanac"]["hours"]) == 13, "almanac preserves both partial Zi-hour segments")
        self.check(bool(calendar["almanac"]["sourceURL"]), "almanac includes source attribution")
        context = self.read("context", {"profile": profile_id, "date": self.date})
        self.check(context["strengthBasis"]["source"] == "local_rule",
                   "personal context defaults to versioned local strength rules")
        strength = self.read("strength.show", {"profile": profile_id})
        native_strength = strength["report"]
        self.check(native_strength == context["nativeStrength"]
                   and strength["strengthBasis"] == context["strengthBasis"],
                   "strength command and daily context share the same report and precedence")
        self.check(bool(native_strength["ruleVersion"])
                   and native_strength["ruleVersion"] == context["strengthBasis"]["ruleVersion"]
                   and {"month", "stems", "roots", "support", "drain"}.issubset(
                       {entry["id"] for entry in native_strength["evidence"]})
                   and all(entry["observations"] and entry["ruleNote"] for entry in native_strength["evidence"]),
                   "local strength report carries versioned month, stems, roots, support and drain evidence")
        self.check(context["personalReading"]["strength"] == native_strength["assessment"],
                   "daily interpretation uses the actual local assessment, including undetermined results")
        initial_hexagrams = self.read("hexagrams.show", {"profile": profile_id, "date": self.date})
        self.check(initial_hexagrams["profile"]["revision"] == profile_revision
                   and initial_hexagrams["hexagrams"] == context["hexagrams"],
                   "hexagrams command and context share deterministic facts and profile revision")
        gua = initial_hexagrams["hexagrams"]
        marked_gua = [gua["xianTian"], gua["houTian"]] + [gua[key]["marked"] for key in ["year", "month", "day"]]
        self.check(all(1 <= item["hexagram"]["number"] <= 64
                       and len(item["hexagram"]["lines"]) == 6
                       and all(type(line) is bool for line in item["hexagram"]["lines"])
                       and 1 <= item["linePosition"] <= 6 for item in marked_gua),
                   "natal and year/month/day hexagrams all carry six ordered lines and marked positions")
        instant = datetime.fromisoformat(gua["instant"].replace("Z", "+00:00"))
        self.check(all(datetime.fromisoformat(gua[key]["start"].replace("Z", "+00:00")) <= instant
                       < datetime.fromisoformat(gua[key]["end"].replace("Z", "+00:00"))
                       for key in ["year", "month", "day"])
                   and len(gua["lifeSegments"]) == 12 and bool(gua["methodNotes"]),
                   "hexagrams expose containing half-open periods, life segments and rule notes")
        self.check({p["period"] for p in context["personalReading"]["periods"]} == {"year", "month", "day"},
                   "personal context includes year, month and day relationships")

        knowledge = self.read("knowledge.search", {"query": "旺衰"})
        self.check(any(i["id"] == "strength-analysis" for i in knowledge["items"]),
                   "bundled strength knowledge is searchable")
        reference = self.read("knowledge.read", {"id": "strength-analysis"})
        self.check(bool(reference["content"]) and reference["executable"] is False,
                   "knowledge read returns source text without execution")
        self.request("knowledge.read", {"id": "../../etc/passwd"}, error="not_found")
        self.check(True, "knowledge IDs cannot read arbitrary filesystem paths")

        insight_input = {
            "date": self.date, "profileID": profile_id, "profileRevision": profile_revision,
            "title": "合成旺衰分析", "body": "仅用于接口验收。此处是合成证据，不是对真实用户的命理结论。",
            "author": "CLI 合成验收", "strengthAssessment": "weak",
        }
        insight = self.write("insights.save", insight_input)
        insight_id = insight["id"]
        insight_shown = self.read("insights.show", {"id": insight_id})
        self.check(insight_shown["note"]["body"] == insight_input["body"] and not insight_shown["stale"],
                   "full insight body is readable and current")
        self.check(insight_shown["note"]["source"] == "agent", "CLI insight preserves Agent source")
        summaries = self.read("insights.list", {"profile": profile_id, "date": self.date})["notes"]
        self.check(len(summaries) == 1 and "body" not in summaries[0]["note"],
                   "insight list returns summaries without private body text")
        context = self.read("context", {"profile": profile_id, "date": self.date})
        self.check(context["strengthBasis"]["source"] == "agent_insight"
                   and context["strengthBasis"]["noteID"] == insight_id
                   and context["personalReading"]["strength"] == "weak",
                   "current Agent strength assessment drives personal context")
        self.check(all("body" not in n["note"] for n in context["notes"]),
                   "daily context does not silently include note bodies")
        self.request("journal.create", dict(insight_input), error="invalid_request")
        self.check(True, "journal cannot supply a strength assessment")

        journal = self.write("journal.create", {
            "date": self.date, "profileID": profile_id, "title": "合成日记",
            "body": "今天准备会议材料。仅为合成验收记录。", "author": "CLI 合成验收",
        })
        journal_id = journal["id"]
        journal2 = self.write("journal.update", {
            "id": journal_id, "revision": journal["revision"], "body": "已准备会议提纲。合成验收第二版。",
        })
        self.check(self.read("journal.show", {"id": journal_id})["note"]["body"] == journal2["record"]["body"],
                   "journal update and full-body read agree")
        self.request("journal.update", {
            "id": journal_id, "revision": journal["revision"], "body": "过期版本不应覆盖正文。",
        }, error="revision_conflict")
        self.request("insights.show", {"id": journal_id}, error="wrong_kind")
        self.check(True, "journal and insight record types stay distinct")

        event_input = {
            "title": "合成会议 " + self.run_id[-6:], "start": self.date + "T15:00:00+08:00",
            "end": self.date + "T16:00:00+08:00", "reminderMinutes": 10,
            "notes": "仅用于预览验收，不能发送真实通知。", "destination": "local",
        }
        event_request = self.run_id + "-event"
        event = self.write("events.create", event_input, event_request)
        event_id = event["id"]
        replay = self.request("events.create", event_input, request_id=event_request)
        self.check(replay.get("replayed") is True and replay["result"] == event,
                   "reminder creation is idempotent")
        self.check(event["notification"]["state"] == "preview_suppressed",
                   "preview reminder does not schedule real notifications")
        rows = self.read("events.list", {"from": self.date, "to": "2026-09-21"})["occurrences"]
        self.check(sum(row["record"]["event"]["id"] == event_id for row in rows) == 1,
                   "event range contains exactly one created occurrence")
        self.check(self.read("events.show", {"id": event_id})["event"]["reminderMinutes"] == 10,
                   "event read retains requested reminder")
        event2 = self.write("events.update", {
            "id": event_id, "revision": event["revision"], "title": "合成会议已改名",
        })
        self.request("events.update", {
            "id": event_id, "revision": event["revision"], "title": "过期版本不应覆盖会议",
        }, error="revision_conflict")
        self.request("events.delete", {
            "id": event_id, "revision": event2["revision"], "title": "删除操作不能夹带字段",
        }, error="unknown_field")
        self.check(self.read("events.show", {"id": event_id})["revision"] == event2["revision"],
                   "invalid delete leaves event unchanged")
        self.request("tasks.complete", {"id": event_id, "revision": event2["revision"]}, error="wrong_kind")
        self.request("tasks.complete", {
            "id": event_id, "revision": event2["revision"], "isTask": True,
        }, error="unknown_field")
        self.request("tasks.complete", {
            "id": event_id, "revision": event2["revision"], "title": "完成时不能改名",
        }, error="unknown_field")
        self.check(self.read("events.show", {"id": event_id})["event"]["isTask"] is False,
                   "tasks complete cannot convert a normal event into a task")
        task = self.write("events.create", {
            "title": "合成无日期待办", "start": self.date + "T09:00:00+08:00",
            "isTask": True, "taskHasDueDate": False, "taskDueHasTime": False,
        })
        task_done = self.write("tasks.complete", {"id": task["id"], "revision": task["revision"]})
        self.check(task_done["record"]["isCompleted"] is True, "local task can be completed")
        task_shown = self.read("tasks.show", {"id": task["id"]})["event"]
        self.check(task_shown["taskHasDueDate"] is False and task_shown["isCompleted"] is True,
                   "completed undated task remains readable")
        tasks = self.read("tasks.list")
        self.check(any(t["event"]["id"] == task["id"] for t in tasks["tasks"]),
                   "task list includes completed undated records")

        unknown = self.write("profiles.create", dict(
            profile_input, name="合成时刻不详", birthTimeKnown=False,
        ))
        unknown_charts = self.read("chart.show", {"profile": unknown["id"]})["charts"]
        self.check(all(c["pillars"]["hour"] is None and c["hasUnknownBirthHour"] for c in unknown_charts),
                   "unknown birth hour remains unknown in every candidate chart")
        self.request("profiles.update", {
            "id": unknown["id"], "revision": unknown["revision"], "birthTimeKnown": True,
        }, error="missing_field")
        self.check(self.read("profiles.show", {"id": unknown["id"]})["profile"]["birthTimeKnown"] is False,
                   "unknown-to-known update requires explicit birth hour and minute")
        unavailable = self.request("hexagrams.show", {"profile": unknown["id"], "date": self.date},
                                   error="hexagrams_unavailable")
        unknown_context = self.read("context", {"profile": unknown["id"], "date": self.date})
        self.check("出生时刻" in unavailable["error"]["message"]
                   and unknown_context["hexagrams"] is None
                   and bool(unknown_context["hexagramsUnavailable"])
                   and unknown_context["nativeStrength"]["assessment"] == "unspecified",
                   "unknown birth time produces explicit unavailable hexagrams and undecided strength")
        no_gender = self.write("profiles.create", dict(profile_input, name="合成未填排盘性别", luckGender=None))
        unavailable = self.request("hexagrams.show", {"profile": no_gender["id"], "date": self.date},
                                   error="hexagrams_unavailable")
        gender_context = self.read("context", {"profile": no_gender["id"], "date": self.date})
        self.check("性别" in unavailable["error"]["message"]
                   and gender_context["hexagrams"] is None
                   and "性别" in gender_context["hexagramsUnavailable"],
                   "missing gender is never guessed for personal hexagrams")
        for invalid in ["2026-02-30", "2026-9-20", "2026-09-20junk", "2100-01-01"]:
            self.request("hexagrams.show", {"profile": profile_id, "date": invalid},
                         error={"invalid_date", "invalid_request"})
        for invalid in ["24:00", "9:00", "12:60", "12:00junk"]:
            self.request("hexagrams.show", {"profile": profile_id, "date": self.date, "at": invalid},
                         error="invalid_time")
        self.check(True, "hexagram queries enforce real supported dates and strict clock syntax")

        for invalid in ["2026-02-30", "2026-9-20", "2026-09-20junk"]:
            self.request("calendar.day", {"date": invalid}, error={"invalid_date", "invalid_request"})
        self.check(True, "calendar rejects nonexistent and malformed civil dates")
        for invalid in ["2026-02-30T15:00:00+08:00", self.date + "T15:00:00+25:00",
                        self.date + "T15:00:00+08:00junk", self.date + "T15:00:00"]:
            self.request("events.create", {"title": "非法时间合成记录", "start": invalid}, error="invalid_request")
        self.check(True, "event timestamps require real dates, valid offsets and exact syntax")
        self.request("events.create", dict(event_input, destination=42), error="unsupported_destination")
        self.request("events.create", dict(event_input, destination="apple"), error="unsupported_destination")
        self.check(True, "CLI refuses unsupported Apple and nonstring destinations")
        self.request("events.create", dict(event_input, id=str(uuid.uuid4())), error="unknown_field")
        self.request("profiles.create", dict(profile_input, revision="caller-supplied"), error="unknown_field")
        self.check(True, "create rejects caller-supplied identity and revision controls")

        changed = self.write("profiles.update", {
            "id": profile_id, "revision": profile_revision, "birthHour": 15, "birthMinute": 31,
        })
        self.check(self.read("insights.show", {"id": insight_id})["stale"] is True,
                   "birth profile changes mark old analysis stale")
        context = self.read("context", {"profile": profile_id, "date": self.date})
        self.check(context["strengthBasis"]["source"] == "local_rule"
                   and context["personalReading"]["strength"] == context["nativeStrength"]["assessment"],
                   "stale Agent analysis falls back to recomputed local rules")
        changed_hexagrams = self.read("hexagrams.show", {"profile": profile_id, "date": self.date})
        self.check(changed_hexagrams["profile"]["revision"] == changed["revision"]
                   and changed_hexagrams["hexagrams"] == context["hexagrams"]
                   and changed_hexagrams["hexagrams"]["xianTian"] != initial_hexagrams["hexagrams"]["xianTian"],
                   "changing the birth-hour branch recomputes personal hexagrams without stale cache")
        self.request("insights.save", dict(insight_input, title="过期档案分析"), error="profile_revision_conflict")
        revised_input = dict(insight_input, id=insight_id, revision=insight["revision"],
                             profileRevision=changed["revision"], body="合成资料更新后的证据。")
        refreshed = self.write("insights.save", revised_input)
        self.check(not self.read("insights.show", {"id": insight_id})["stale"],
                   "analysis can be refreshed against current profile revision")
        self.request("insights.save", dict(revised_input, body="过期日笺不能覆盖"), error="revision_conflict")
        self.check(self.read("insights.show", {"id": insight_id})["revision"] == refreshed["revision"],
                   "stale insight update preserves current content")
        self.write("profiles.update", {
            "id": profile_id, "revision": changed["revision"], "strengthAssumption": "strong",
        })
        context = self.read("context", {"profile": profile_id, "date": self.date})
        self.check(context["strengthBasis"]["source"] == "profile_override"
                   and context["personalReading"]["strength"] == "strong",
                   "explicit profile assumption takes precedence over Agent analysis")

    def cleanup(self):
        errors = []
        # Notes/events precede profiles because they may reference a profile.
        records = sorted(self.created, key=lambda item: item[0] == "profiles")
        for domain, identifier in records:
            try:
                current = self.read(domain + ".show", {"id": identifier})
                params = {"id": identifier, "revision": current["revision"]}
                request_id = self.run_id + "-cleanup-" + identifier
                removed = self.request(domain + ".delete", params, request_id=request_id)
                self.check(removed["result"]["deleted"] is True, domain + " synthetic record removed")
                replay = self.request(domain + ".delete", params, request_id=request_id)
                self.check(replay.get("replayed") is True, domain + " deletion retry is idempotent")
                self.request(domain + ".show", {"id": identifier}, error="not_found")
            except Exception as exc:
                errors.append("%s %s: %s" % (domain, identifier, exc))
        if errors:
            raise AssertionError("Synthetic cleanup incomplete:\n" + "\n".join(errors))


def main():
    project = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=pathlib.Path,
                        default=project / "build/灵性日历预览.app/Contents/MacOS/lingxi",
                        help="Path to a shipped lingxi binary; connection always uses --preview")
    args = parser.parse_args()
    if not args.cli.is_file():
        parser.error("CLI missing; build and launch the preview app first: " + str(args.cli))
    suite = PreviewSuite(args.cli.resolve())
    failure = None
    try:
        suite.execute()
    except Exception as exc:
        failure = exc
    finally:
        try:
            suite.cleanup()
        except Exception as cleanup_error:
            failure = RuntimeError(str(failure) + "\n" + str(cleanup_error)) if failure else cleanup_error
    if failure:
        print("FAIL " + str(failure), file=sys.stderr)
        return 1
    print("Preview CLI integration passed: %d checks; synthetic records removed." % suite.checks)
    return 0


if __name__ == "__main__":
    sys.exit(main())
