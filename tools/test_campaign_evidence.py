"""The strict gate must not recycle a prior campaign or mix source revisions."""
import os
from pathlib import Path
import tempfile
import unittest
from verify_original import campaign_evidence_rejection, campaign_run_matches, evidence_fingerprint


class CampaignEvidenceTest(unittest.TestCase):
    def test_invocation_identity(self):
        rows = [{"provenance": {"evidence_run_id": "current"}}]
        self.assertTrue(campaign_run_matches(rows, "current"))
        self.assertFalse(campaign_run_matches(rows, "historical"))
        self.assertFalse(campaign_run_matches([], "current"))
        self.assertFalse(campaign_run_matches([{}], "current"))
        self.assertFalse(campaign_run_matches([{"provenance": {"evidence_run_id": ""}}], ""))

    def test_eligibility(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "campaign.json"
            inputs = dict(requested=True, probe_ok=True, started_ns=2_000_000_000,
                          path=output, before="same", after="same")
            self.assertIn("missing fresh", campaign_evidence_rejection(**inputs))
            output.write_text("[]")
            os.utime(output, ns=(1_000_000_000, 1_000_000_000))
            self.assertIn("missing fresh", campaign_evidence_rejection(**inputs))
            os.utime(output, ns=(3_000_000_000, 3_000_000_000))
            self.assertIsNone(campaign_evidence_rejection(**inputs))
            self.assertIn("not run", campaign_evidence_rejection(**(inputs | {"requested": False})))
            self.assertIn("did not finish", campaign_evidence_rejection(**(inputs | {"probe_ok": False})))
            self.assertIn("changed", campaign_evidence_rejection(**(inputs | {"after": "other"})))

    def test_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ("godot/scripts", "godot/tests", "godot/data", "tools", "extract"):
                (root / folder).mkdir(parents=True)
            (root / "godot/project.godot").write_text("config")
            extractor = root / "extract_all.py"
            extractor.write_text("original extractor")
            script = root / "godot/scripts/Battle.gd"
            script.write_text("original")
            before = evidence_fingerprint(root)
            (root / "HANDOVER.md").write_text("unrelated notes")
            self.assertEqual(before, evidence_fingerprint(root))
            script.write_text("different rules")
            self.assertNotEqual(before, evidence_fingerprint(root))
            before = evidence_fingerprint(root)
            extractor.write_text("different extractor")
            self.assertNotEqual(before, evidence_fingerprint(root))
            before = evidence_fingerprint(root)
            (root / "extract/txt.py").write_text("different source decoder")
            self.assertNotEqual(before, evidence_fingerprint(root))
            before = evidence_fingerprint(root)
            (root / "godot/data/m4.json").write_text("different generated data")
            self.assertNotEqual(before, evidence_fingerprint(root))


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(CampaignEvidenceTest))
    if result.wasSuccessful():
        print("CAMPAIGN_EVIDENCE PASS")
    raise SystemExit(not result.wasSuccessful())
