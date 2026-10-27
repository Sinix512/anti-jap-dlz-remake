"""Fail-closed joint route evidence, not an ID-union or a gameplay simulator.

Only the trusted current-invocation native probe can supply eligible artifacts.
Synthetic unit fixtures test this contract; they are never acceptance evidence.
"""
from __future__ import annotations

from typing import Any

SCHEMA = "dlz-natural-routes-v1"
MODES = {"simulation": 36, "fiction": 40}
THRESHOLDS = (2800, 3000, 3300, 3600)
INTERLUDES = {44: 3, 45: 4, 46: 9}


def _require(ok: bool, message: str, errors: list[str]) -> None:
    if not ok:
        errors.append(message)


def _flag(state: dict, flag: int) -> int:
    return int(state["flags"].get(str(flag), 0))


def _full_matches(full: dict, route: dict) -> bool:
    """Compare fields unaffected by launch templates/start-phase NPC writes."""
    return all(full[key] == route[short] for key, short in (
        ("campaign_index", "index"), ("campaign_completed", "completed"),
        ("main_score_snapshot", "frozen"), ("score_total", "score")))


def validate_chain(data: Any, run_id: str, chain_id: str, mode: str) -> dict:
    errors: list[str] = []
    try:
        _require(isinstance(data, dict) and data["schema"] == SCHEMA, "unsupported route schema", errors)
        _require(mode in MODES and data["route"] == mode, "wrong route mode", errors)
        _require(bool(run_id and chain_id) and data["run_id"] == run_id and data["chain_id"] == chain_id,
                 "foreign invocation/chain identity", errors)
        _require(data["fresh"] is True and data["creation"] == {"face": 103, "unit": 4, "wuli": 100, "difficulty": 1},
                 "missing lawful fresh normal creation", errors)
        initial = data["initial_state"]
        _require(initial["campaign_index"] == 0 and initial["campaign_completed"] == [] and
                 initial["hidden_done"] == [] and initial["score_total"] == 0 and
                 initial["main_score_snapshot"] == 0 and initial["difficulty"] == 1,
                 "initial state is not a new L00 game", errors)
        _require(not data["errors"], "native probe has story/driver errors", errors)
        policy = data["interlude_policy"]
        _require(policy["rng_seed_override"] is False and policy["max_visits"] == 64 and
                 0 <= policy["actual_visits"] <= policy["max_visits"], "invalid natural interlude policy", errors)
        trace = data["route_trace"]
        _require([e["seq"] for e in trace] == list(range(len(trace))), "trace is reordered/truncated/spliced", errors)
        _require(all(e["kind"] in {"resident", "launch", "commit", "hidden", "close"} for e in trace),
                 "unknown route event", errors)
        rows = data["rows"]
        _require(bool(rows), "no observed battle", errors)
        _require(policy["actual_visits"] == sum(e["kind"] == "interlude_resident" for e in data["navigation_inputs"]),
                 "interlude visit count lacks actual viewport inputs", errors)
        completed: list[int] = []
        main: list[int] = []
        hidden: list[int] = []
        interludes: list[int] = []
        used_launch: set[int] = set()
        used_commit: set[int] = set()
        frozen = 0
        total = 0
        lost = False
        for n, row in enumerate(rows):
            idx = int(row["idx"])
            p = row["provenance"]
            _require(p == {"fresh": True, "difficulty": 1, "campaign_path": True,
                           "evidence_run_id": run_id, "chain_id": chain_id, "route": mode},
                     f"row{n}: foreign/non-fresh provenance", errors)
            _require(not lost and 0 <= idx < 47, f"row{n}: continued after defeat/invalid index", errors)
            _require(not row["retry_attempts"], f"row{n}: unimplemented retry provenance", errors)
            launch_seq = row["route_launch_seq"]
            launch = trace[launch_seq]
            _require(launch_seq not in used_launch and launch["kind"] == "launch" and
                     launch["extra"]["idx"] == idx and launch["extra"]["standalone"] is False and
                     launch["before"]["index"] == idx, f"row{n}: no unique natural Campaign launch", errors)
            used_launch.add(launch_seq)
            before, after = row["state_before"], row["state_after"]
            _require(before["campaign_completed"] == completed and before["score_total"] == total and
                     before["main_score_snapshot"] == frozen and _full_matches(before, launch["after"]),
                     f"row{n}: entry history/score/source discontinuity", errors)
            if idx < 36:
                _require(idx == len(main) and not hidden, f"row{n}: skipped/replayed mainline", errors)
            elif idx < 44:
                _require(main == list(range(36)) and idx == MODES[mode] + len(hidden) and
                         len(hidden) < 4 and frozen >= THRESHOLDS[min(len(hidden), 3)],
                         f"row{n}: wrong/mixed/unearned hidden route", errors)
            else:
                _require(idx not in interludes, f"row{n}: repeated one-shot interlude", errors)
                flag = INTERLUDES[idx]
                sources = [e for e in trace if e["kind"] == "resident" and
                           e["extra"]["town"] == 0 and e["after"]["index"] == idx and
                           e["before"]["index"] != idx and _flag(e["before"], flag) == 0 and
                           _flag(e["after"], flag) == 1 and
                           _flag(e["after"], 91) == e["before"]["index"] and
                           e["after"]["completed"] == launch["before"]["completed"] and
                           e["frame"] <= launch["frame"] and
                           all(_flag(e["before"], f) != 0 for i, f in INTERLUDES.items() if i < idx)]
                _require(len(sources) == 1 and _flag(launch["before"], flag) == 1,
                         f"row{n}: missing natural town0 one-shot/return source", errors)
                if len(sources) == 1:
                    _require(any(e["kind"] in {"interlude_resident", "mission_resident"} and
                                 e["before"] == sources[0]["before"] and e["after"] == sources[0]["after"]
                                 for e in data["navigation_inputs"]),
                             f"row{n}: interlude lacks actual resident viewport action", errors)
            flow = row["campaign_flow"]
            report = flow["report"]
            victory = row["result"]["result"] == "victory"
            _require(row["result"]["result"] in {"victory", "defeat"} and report["idx"] == idx and
                     report["victory"] is victory and not flow["story_errors"] and not row["legality"]["errors"],
                     f"row{n}: invalid result/settlement/permissions", errors)
            if victory:
                _require(flow["result_acknowledged"] is True, f"row{n}: missing actual report acknowledgement", errors)
                commit_seq = row["route_commit_seq"]
                commit = trace[commit_seq]
                _require(commit_seq not in used_commit and commit_seq > launch_seq and commit["kind"] == "commit" and
                         commit["extra"]["idx"] == idx and commit["extra"]["report"]["result_committed"] is True,
                         f"row{n}: no unique real result commit", errors)
                used_commit.add(commit_seq)
                total += int(report["score"])
                completed.append(idx)
                if idx < 36:
                    main.append(idx)
                elif idx < 44:
                    hidden.append(idx)
                else:
                    interludes.append(idx)
                if idx == 35:
                    frozen = total
                _require(after["campaign_completed"] == completed and after["score_total"] == total and
                         after["main_score_snapshot"] == frozen and _full_matches(after, commit["after"]),
                         f"row{n}: settlement history/score/freeze discontinuity", errors)
                expected_index = idx + 1 if idx < 44 else _flag(launch["before"], 91)
                _require(commit["after"]["index"] == expected_index,
                         f"row{n}: invalid progression/interlude return", errors)
                if idx == 45:
                    _require(commit["after"]["item56"] == commit["before"]["item56"] + 1,
                             "L45 reward not granted exactly once by phase commit", errors)
            else:
                lost = True
                _require(after["campaign_completed"] == completed and after["score_total"] == total and
                         after["main_score_snapshot"] == frozen and "route_commit_seq" not in row,
                         f"row{n}: defeat advanced or changed score", errors)
        _require({e["seq"] for e in trace if e["kind"] == "commit"} == used_commit,
                 "unobserved/duplicated victory commit", errors)
        # An auto-launched next battle at a short-run boundary is allowed but
        # cannot count as a win. No unobserved launches in the middle of a chain.
        unused = [e for e in trace if e["kind"] == "launch" and e["seq"] not in used_launch]
        _require(len(unused) <= 1 and all(e["seq"] > max(used_commit | used_launch, default=-1) for e in unused),
                 "unobserved launch inside played chain", errors)
        choices = [e for e in data["native_inputs"] if e["kind"] == "hidden_choice_input"]
        selections = [e for e in trace if e["kind"] == "hidden"]
        if hidden or selections:
            _require(len(choices) == len(selections) == 1 and choices[0]["mode"] == mode and
                     choices[0]["before"]["frozen_score"] == frozen and choices[0]["before"]["hidden_unlocked"] is True and
                     selections[0]["extra"]["mode"] == mode and selections[0]["before"]["frozen"] == frozen and
                     all(i in selections[0]["before"]["completed"] for i in range(36)) and
                     selections[0]["after"]["index"] == MODES[mode] and
                     (mode != "fiction" or (_flag(selections[0]["before"], 85) != 2 and _flag(selections[0]["after"], 85) == 2)),
                     "hidden route has no actual choice from this L35 freeze", errors)
        for event in trace:
            if 35 in event["before"]["completed"]:
                _require(event["before"]["frozen"] == frozen and event["after"]["frozen"] == frozen,
                         "frozen main score changed after L35", errors)
        final = data["final_state"]
        _require(final["campaign_completed"] == completed and final["main_score_snapshot"] == frozen and
                 final["score_total"] == total, "final history/source discontinuity", errors)
        closed = data["stop"]["boundary"] == "process_close"
        close_events = [e for e in trace if e["kind"] == "close"]
        close_inputs = [e for e in data["native_inputs"] if e["kind"] == "process_close_requested"]
        _require(closed == (len(close_events) == len(close_inputs) == 1), "missing/duplicate natural close", errors)
        _require(sum(e["kind"].endswith("/OriginalVictoryReport.gd") and e["stage"] == "wait" for e in data["report_inputs"]) == len(completed),
                 "victories lack distinct real report viewport acknowledgements", errors)
        allowed = list(range(MODES[mode], MODES[mode] + sum(frozen >= t for t in THRESHOLDS)))
        if closed:
            _require(main == list(range(36)) and hidden == allowed and not lost and
                     data["ending_flow"][:2] == ["END", "chapter35"] and data["ending_flow"][-1] == "finale",
                     "premature or unnatural finale", errors)
            _require(close_events[0]["extra"]["ending_flow"] == data["ending_flow"],
                     "close and END/chapter/finale sources disagree", errors)
        return {"valid": not errors, "errors": errors, "won": completed, "mainline_won": main,
                "hidden_won": hidden, "interludes_won": interludes, "frozen_score": frozen,
                "natural_terminal": closed and not errors, "full_branch": hidden == list(range(MODES[mode], MODES[mode] + 4)),
                "boundary": data["stop"]["boundary"]}
    except (KeyError, TypeError, ValueError, IndexError, AttributeError, OverflowError) as exc:
        errors.append(f"malformed route evidence: {type(exc).__name__}: {exc}")
        return {"valid": False, "errors": errors, "won": [], "natural_terminal": False, "full_branch": False}


def joint_routes(chains: list[dict], run_id: str, identities: dict[str, str]) -> dict:
    """Only independent current-invocation chains can jointly cover the47."""
    errors: list[str] = []
    _require(set(identities) == set(MODES) and len(set(identities.values())) == 2,
             "two independent chain identities required", errors)
    reports = {}
    _require(len(chains) == 2 and all(isinstance(c, dict) for c in chains), "two route artifacts required", errors)
    for mode in MODES:
        matching = [c for c in chains if isinstance(c, dict) and c.get("route") == mode]
        if len(matching) != 1:
            errors.append(f"exactly one independent {mode} chain required")
            continue
        reports[mode] = validate_chain(matching[0], run_id, identities.get(mode, ""), mode)
        errors.extend(f"{mode}: {e}" for e in reports[mode]["errors"])
    won = sorted({i for r in reports.values() if r["valid"] for i in r["won"]})
    complete = not errors and len(reports) == 2 and all(r["natural_terminal"] and r["full_branch"] for r in reports.values()) and won == list(range(47))
    return {"valid": not errors, "errors": errors, "chains": reports, "won": won, "complete": complete,
            "scope": "joint natural routes plus legal resolver combat; not human/all-mouse47"}
