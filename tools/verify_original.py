"""Evidence-scoped original-rules regression. Never treats boosted M7–M12 as play proof."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

from campaign_routes import joint_routes

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
TESTS = {
    "NativeEndingUI": "NATIVE_ENDING_UI PASS",
    "NativeRouteInputTest": "NATIVE_ROUTE_INPUT checks=26 failures=0",
    "NativeCampaignRouteTest": "NATIVE_CAMPAIGN_ROUTE PASS",
    "CampaignRoutes": "CAMPAIGN_ROUTES PASS",
    "OriginalEndingTest": "ORIGINAL_ENDING PASS",
    "OriginalCutsceneTest": "ORIGINAL_CUTSCENE PASS",
    "OriginalRouteTransactionTest": "ORIGINAL_ROUTE_TRANSACTION PASS",
    "OriginalInterludePartyTest": "INTERLUDE_PARTY checks=30 failures=0",
    "LegalProbeRouteTest": "LEGAL_PROBE_ROUTE PASS",
    "CampaignEvidence": "CAMPAIGN_EVIDENCE PASS",
    "StoryStreamContract": "STORY_STREAM_CONTRACT PASS",
    "NativeSpritePalette": "NATIVE_SPRITE_PALETTE PASS",
    "NativeBattleANM": "NATIVE_BATTLE_ANM PASS",
    "NativeInventoryUI": "NATIVE_INVENTORY_UI PASS",
    "NativeCreationUI": "NATIVE_CREATION_UI PASS",
    "NativeTitleUI": "NATIVE_TITLE_UI PASS",
    "NativeStrategicUI": "NATIVE_STRATEGIC_UI PASS",
    "NativeSaveUI": "NATIVE_SAVE_UI PASS",
    "NativeStoryReportUI": "NATIVE_STORY_REPORT_UI PASS",
    "NativeServicesUI": "NATIVE_SERVICES_UI PASS",
    "ScriptCheck": "SCRIPT_CHECK failures=0",
    "OriginalSystemsTest": "ORIGINAL_SYSTEMS checks=39 failures=0",
    "OriginalItemsTest": "ORIGINAL_ITEMS checks=26 failures=0",
    "OriginalMinesTest": "ORIGINAL_MINES checks=30 failures=0",
    "OriginalFactionTest": "ORIGINAL_FACTION checks=36 failures=0",
    "YulaiCrateFactionTest": "YULAI_CRATE_FACTION PASS",
    "OriginalTriggerPredicateTest": "ORIGINAL_TRIGGER_PREDICATE checks=60 failures=0",
    "OriginalRoundTailTest": "ORIGINAL_ROUND_TAIL checks=41 failures=0",
    "PublicRoundForecastTest": "PUBLIC_ROUND_FORECAST checks=605 failures=0",
    "PublicOutcomeTreeTest": "PUBLIC_OUTCOME_TREE checks=2205 failures=0",
    "ForecastCandidateSetTest": "FORECAST_CANDIDATE_SET checks=127 failures=0",
    "H2WindowPlannerTest": "H2_WINDOW_PLANNER checks=30 failures=0",
    "LateEscortPolicyTest": "LATE_ESCORT_POLICY checks=12 failures=0",
    "CapturedFoodProvisionTest": "CAPTURED_FOOD_PROVISION checks=12 failures=0",
    "TriggerTest": "TRIGGER_TEST_OK",
    "OriginalCombatTest": "ORIGINAL_COMBAT checks=56 failures=0",
    "AttackAreaPresentationTest": "ATTACK_AREA_PRESENTATION_OK",
    "SkillAreaPresentationTest": "SKILL_AREA_PRESENTATION_OK",
    "OriginalRelationsTest": "ORIGINAL_RELATIONS checks=168 failures=0",
    "OriginalMediaTest": "ORIGINAL_MEDIA checks=86 failures=0",
    "OriginalActionOrderTest": "ORIGINAL_ACTION_ORDER checks=34 failures=0",
    "OriginalChestTest": "ORIGINAL_CHEST checks=54 failures=0",
    "ModalEntryInputTest": "MODAL_ENTRY_INPUT PASS",
    "AutomaticCameraTest": "AUTOMATIC_CAMERA checks=31 failures=0",
    "MineActionContinuityTest": "MINE_ACTION_CONTINUITY checks=18 failures=0",
    "OriginalMenuTest": "ORIGINAL_MENU checks=68 failures=0",
    "OriginalToolbarTest": "ORIGINAL_TOOLBAR checks=44 failures=0",
    "OriginalCursorTest": "ORIGINAL_CURSOR checks=12 failures=0",
    "OriginalCharacterCreateTest": "ORIGINAL_CREATION checks=64 failures=0",
    "OriginalStrategicTest": "ORIGINAL_STRATEGIC PASS",
    "OriginalServicesTest": "ORIGINAL_SERVICES checks=64 failures=0",
    "TownCatalog": "TOWN_CATALOG PASS",
    "ShopCatalogTest": "SHOP_CATALOG PASS",
    "ShopQuantityTest": "SHOP_QUANTITY PASS",
    "ShopConvenienceTest": "SHOP_CONVENIENCE_OK",
    "OriginalLootBoundaryTest": "ORIGINAL_LOOT_BOUNDARY checks=40 failures=0",
    "OriginalResultTransactionTest": "ORIGINAL_RESULT_TRANSACTION checks=28 failures=0",
    "OriginalJourneyTest": "ORIGINAL_JOURNEY checks=17 failures=0",
    "OriginalTitleTest": "ORIGINAL_TITLE checks=29 failures=0",
    "OriginalTitlePagesTest": "ORIGINAL_TITLE_PAGES checks=38 failures=0",
    "OriginalSavePickerTest": "ORIGINAL_SAVE_PICKER checks=31 failures=0",
    "OriginalPlacementTest": "ORIGINAL_PLACEMENT checks=48 failures=0",
    "LegalProbePermissionsTest": "LEGAL_PROBE_PERMISSIONS checks=39 failures=0",
    "OriginalRangeMaskTest": "ORIGINAL_RANGE_MASK_OK",
    "OriginalDeathMixTest": "ORIGINAL_DEATH_MIX checks=422 failures=0",
    "OriginalPresentationTest": "ORIGINAL_PRESENTATION checks=16 failures=0",
    "OriginalInfoLayoutTest": "ORIGINAL_INFO_LAYOUT checks=175 failures=0",
    "OriginalFidelityTest": "ORIGINAL_FIDELITY failures=0",
    "StateCodecPackTest": "STATE_CODEC_PACK PASS",
    "ResumeRetryTest": "RESUME_RETRY checks=25 failures=0",
    "OriginalStoryReportTest": "ORIGINAL_STORY_REPORT PASS",
    "OriginalDefeatTest": "ORIGINAL_DEFEAT checks=33 failures=0",
    "OriginalUIInputTest": "ORIGINAL_UI_INPUT checks=32 failures=0",
    "OriginalInventoryTest": "ORIGINAL_INVENTORY checks=50 failures=0",
    "NativeEconomyTest": "NATIVE_ECONOMY checks=23 failures=0",
    "InputProbe": "INPUT_PROBE_OK",
}

def evidence_fingerprint(root: Path = ROOT) -> str:
    """Bind a run to the tested source/data, not unrelated historical logs."""
    paths = set()
    for folder in ("godot/scripts", "godot/tests", "tools"):
        for path in (root / folder).rglob("*"):
            if path.suffix in {".gd", ".gdshader", ".py", ".json"}:
                paths.add(path)
    paths.update((root / "godot/data").glob("*.json"))
    paths.update((root / "extract").glob("*.py"))
    paths.add(root / "extract_all.py")
    paths.add(root / "godot/project.godot")
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()

def campaign_evidence_rejection(*, requested: bool, probe_ok: bool,
                                started_ns: int, path: Path,
                                before: str, after: str) -> str | None:
    if not requested:
        return "campaign not run in this invocation; historical files are not acceptance evidence"
    if not probe_ok:
        return "current campaign probe did not finish cleanly"
    if before != after:
        return "source/data changed during verification; rerun against one revision"
    if not path.exists() or path.stat().st_mtime_ns < started_ns:
        return "missing fresh campaign output from this invocation"
    return None

def campaign_run_matches(rows: list[dict], run_id: str) -> bool:
    return bool(run_id and rows) and all(row.get("provenance", {}).get("evidence_run_id") == run_id for row in rows)

def campaign_row_audit(observations: list[dict], campaign_run_id: str) -> list[dict]:
    legality = []
    for row in observations:
        audit = row.get("legality", {})
        issues = list(audit.get("errors", []))
        if row.get("provenance", {}).get("evidence_run_id") != campaign_run_id:
            issues.append("campaign output belongs to a different invocation")
        if not audit or not row.get("provenance", {}).get("fresh", False):
            issues.append("missing fresh-game permission provenance")
        if not row.get("provenance", {}).get("campaign_path", False):
            issues.append("missing real Campaign launch/settlement provenance")
        if row.get("provenance", {}).get("difficulty") != 1:
            issues.append("normal difficulty1 provenance required")
        flow = row.get("campaign_flow", {})
        issues.extend(flow.get("story_errors", []))
        settled = flow.get("report", {})
        if int(settled.get("idx", -1)) != int(row["idx"]) or bool(settled.get("victory", False)) != (row["result"]["result"] == "victory"):
            issues.append("missing or inconsistent real Campaign result settlement")
        if row["result"]["result"] == "victory" and flow.get("result_acknowledged") is not True:
            issues.append("victory report was not acknowledged through its real input/counter path")
        attempts = list(row.get("retry_attempts", [])) + [row]
        for n, attempt in enumerate(attempts):
            prefix = f"attempt{n+1}: "
            issues.extend(prefix + str(e) for e in attempt.get("legality", {}).get("errors", []))
            if int(attempt.get("idx", -1)) != int(row["idx"]):
                issues.append(prefix + "retry changed level")
            if n < len(attempts) - 1 and attempt.get("result", {}).get("result") != "defeat":
                issues.append(prefix + "retry was not after a recorded defeat")
            aflow = attempt.get("campaign_flow", {})
            issues.extend(prefix + str(e) for e in aflow.get("story_errors", []))
            areport = aflow.get("report", {})
            if int(areport.get("idx", -1)) != int(row["idx"]) or bool(areport.get("victory", False)) != (attempt["result"]["result"] == "victory"):
                issues.append(prefix + "inconsistent real Campaign settlement")
            for kind in ("moves", "actions"):
                keys = [(a["turn"], a["slot"], a.get("epoch", 0)) for a in attempt.get("legality", {}).get(kind, [])]
                if len(keys) != len(set(keys)):
                    issues.append(prefix + "duplicate player " + kind + " without earned renewal")
        legality.append({"idx": int(row["idx"]), "ok": not issues, "issues": issues,
                         "retries": len(row.get("retry_attempts", [])), "moves": len(audit.get("moves", [])), "actions": len(audit.get("actions", []))})
    return legality


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ui", action="store_true", help="render the desktop UI screenshot suite")
    parser.add_argument("--legal", action="store_true", help="observe independent new-game simulation/fiction route probes")
    parser.add_argument("--require-campaign", action="store_true", help="fail until normal-growth coverage actually includes all47")
    parser.add_argument("--campaign-battle-limit", type=int, default=47, choices=range(1,48), help="bounded engineering run; never waives route completion")
    args = parser.parse_args()
    started_ns = time.time_ns()
    revision = evidence_fingerprint()
    campaign_run_id = uuid.uuid4().hex
    chain_ids = {mode: uuid.uuid4().hex for mode in ("simulation", "fiction")}
    campaign_paths = {mode: ROOT / "out" / f"native_campaign_{campaign_run_id}_{mode}.json" for mode in chain_ids}
    logs = ROOT / "out" / "original_validation"
    logs.mkdir(parents=True, exist_ok=True)
    tests = dict(TESTS)
    if args.ui:
        tests["OriginalEndingQA"] = "ORIGINAL_ENDING_UI PASS"
        tests["OriginalUIQA"] = "ORIGINAL_UI_QA_COMPLETE"
        tests["OriginalCreationQA"] = "ORIGINAL_CREATION_UI PASS"
        tests["OriginalTitleQA"] = "ORIGINAL_TITLE_UI PASS"
        tests["OriginalSaveQA"] = "ORIGINAL_SAVE_UI PASS"
        tests["OriginalStrategicQA"] = "ORIGINAL_STRATEGIC_UI PASS"
        tests["OriginalStoryReportQA"] = "ORIGINAL_STORY_REPORT_UI PASS"
        tests["OriginalServicesQA"] = "ORIGINAL_SERVICES_UI PASS"
        tests["SkillAreaPresentationQA"] = "SKILL_AREA_UI PASS"
        tests["ShopConvenienceQA"] = "SHOP_CONVENIENCE_UI PASS"
    if args.legal or args.require_campaign:
        for mode in chain_ids:
            tests[f"NativeCampaignProbe_{mode}"] = "NATIVE_CAMPAIGN completed="
    report = {"scope": "Original-rules regression, not 47-level play acceptance", "tests": [], "campaign_complete": False,
              "source_sha256": revision, "started_ns": started_ns,
              "campaign_run_id": campaign_run_id if args.legal or args.require_campaign else None,
              "campaign_chain_ids": chain_ids, "campaign_artifacts": {mode: str(p) for mode,p in campaign_paths.items()},
              "campaign_battle_limit": args.campaign_battle_limit}
    failed = False
    for test, marker in tests.items():
        command = [GODOT]
        if test != "OriginalUIQA":
            command.append("--headless")
        command += ["--path", str(ROOT / "godot"), "--script", f"res://tests/{test}.gd"]
        if test.startswith("NativeCampaignProbe_"):
            mode = test.removeprefix("NativeCampaignProbe_")
            command = [GODOT, "--headless", "--path", str(ROOT / "godot"), "--script", "res://tests/NativeCampaignProbe.gd", "--",
                       f"--evidence-run-id={campaign_run_id}", f"--chain-id={chain_ids[mode]}", f"--route={mode}",
                       f"--output-tag={campaign_run_id}_{mode}", f"--battle-limit={args.campaign_battle_limit}"]
        if test == "NativeSpritePalette":
            command = [sys.executable, str(ROOT / "tools" / "native_sprite_assets.py"), "--audit"]
        if test == "NativeInventoryUI":
            command = [sys.executable, str(ROOT / "tools" / "verify_inventory_ui.py")]
        if test in {"NativeCreationUI", "OriginalCreationQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_creation_ui.py")]
            if test == "OriginalCreationQA": command.append("--render")
        if test in {"NativeTitleUI", "OriginalTitleQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_title_ui.py")]
            if test == "OriginalTitleQA": command.append("--render")
        if test in {"NativeSaveUI", "OriginalSaveQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_save_ui.py")]
            if test == "OriginalSaveQA": command.append("--render")
        if test in {"NativeStrategicUI", "OriginalStrategicQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_strategy_ui.py")]
            if test == "OriginalStrategicQA": command.append("--render")
        if test in {"NativeStoryReportUI", "OriginalStoryReportQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_story_report_ui.py")]
            if test == "OriginalStoryReportQA": command.append("--render")
        if test in {"NativeServicesUI", "OriginalServicesQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_services_ui.py")]
            if test == "OriginalServicesQA": command.append("--render")
        if test == "SkillAreaPresentationQA":
            command = [sys.executable, str(ROOT / "tools" / "verify_skill_area_ui.py"), "--render"]
        if test == "ShopConvenienceQA":
            command = [sys.executable, str(ROOT / "tools" / "verify_shop_convenience_ui.py"), "--render"]
        if test == "NativeBattleANM":
            command = [sys.executable, str(ROOT / "tools" / "verify_anm_battle.py")]
        if test == "StoryStreamContract":
            command = [sys.executable, str(ROOT / "tools" / "test_story_stream.py")]
        if test in {"NativeEndingUI", "OriginalEndingQA"}:
            command = [sys.executable, str(ROOT / "tools" / "verify_ending_ui.py")]
            if test == "OriginalEndingQA": command.append("--render")
        if test == "CampaignRoutes":
            command = [sys.executable, str(ROOT / "tools" / "test_campaign_routes.py")]
        if test == "TownCatalog":
            command = [sys.executable, str(ROOT / "tools" / "test_town_catalog.py")]
        if test == "CampaignEvidence":
            command = [sys.executable, str(ROOT / "tools" / "test_campaign_evidence.py")]
        path = logs / f"{test}.log"
        try:
            proc = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=3600 if test.startswith("NativeCampaignProbe_") else 180)
            output, code = proc.stdout + proc.stderr, proc.returncode
        except subprocess.TimeoutExpired as exc:
            output = str(exc.stdout or "") + str(exc.stderr or "") + "\nTIMEOUT"
            code = -1
        path.write_text(output)
        # Godot can exit0 after a parse/runtime failure. Require both the marker
        # and clean runtime diagnostics. Exit resource leaks are also failures,
        # not a green test with a warning hidden in its JSON attachment.
        exit_warnings = re.findall(r"(?:WARNING: \d+ ObjectDB instances were leaked at exit[^\n]*|ERROR: \d+ resources still in use at exit[^\n]*)", output)
        errors = [line for line in output.splitlines() if ("SCRIPT ERROR:" in line or line.startswith("ERROR:")) and line not in exit_warnings]
        ok = code == 0 and marker in output and not errors and not exit_warnings
        report["tests"].append({"test": test, "ok": ok, "exit_code": code, "exit_warnings": exit_warnings, "errors": errors, "log": str(path)})
        print(f"{'PASS' if ok else 'FAIL'} {test}" + (" (exit cleanup warning)" if exit_warnings else ""), flush=True)
        if not ok:
            print(output[-4000:])
        failed |= not ok
    campaign_requested = args.legal or args.require_campaign
    final_revision = evidence_fingerprint()
    report["source_consistent"] = revision == final_revision
    failed |= not report["source_consistent"]
    chains = []
    legality = []
    report["campaign_evidence_rejection"] = {}
    for mode, path in campaign_paths.items():
        rejection = campaign_evidence_rejection(
            requested=campaign_requested,
            probe_ok=any(row["test"] == f"NativeCampaignProbe_{mode}" and row["ok"] for row in report["tests"]),
            started_ns=started_ns, path=path, before=revision, after=final_revision)
        report["campaign_evidence_rejection"][mode] = rejection
        if rejection is not None:
            failed |= campaign_requested
            continue
        try:
            data = json.loads(path.read_text())
            chains.append(data)
            rows = data["rows"]
            audit = campaign_row_audit(rows, campaign_run_id)
            for row in audit:
                row["chain"] = mode
            legality.extend(audit)
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            report["campaign_evidence_rejection"][mode] = f"malformed current route artifact: {exc}"
            failed = True
    if campaign_requested:
        joint = joint_routes(chains, campaign_run_id, chain_ids)
        report["campaign_routes"] = joint
        report["campaign_won"] = joint["won"]
        report["campaign_legality"] = legality
        report["campaign_legality_ok"] = bool(legality) and all(row["ok"] for row in legality)
        failed |= not joint["valid"] or not report["campaign_legality_ok"]
        report["campaign_complete"] = joint["complete"] and report["campaign_legality_ok"]
    (logs / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if failed:
        return 1
    print("ORIGINAL_REGRESSION_OK (not full campaign acceptance)")
    if args.require_campaign and not report["campaign_complete"]:
        print("CAMPAIGN_ACCEPTANCE_INCOMPLETE: normal-growth 47-level/branch coverage is not yet proven.")
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
