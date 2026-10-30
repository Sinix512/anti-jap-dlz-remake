#!/usr/bin/env python3
"""Synthetic publication/path tests; no real credentials, devices or player saves."""
from pathlib import Path
from contextlib import redirect_stdout
import io
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_android as android
import check_publication as gate


class PublicationRulesTest(unittest.TestCase):
    def categories(self, text: str, path: str = "example.md") -> set[str]:
        return {finding[2] for finding in gate.inspect(path, text.encode())}

    def test_personal_paths(self):
        for prefix in ("Users", "home", "Volumes", "tmp", "private/tmp"):
            with self.subTest(prefix=prefix):
                self.assertIn("personal-or-temporary-path", self.categories("/" + prefix + "/sample/project"))
        self.assertIn("windows-personal-path", self.categories("C:" + chr(92) + "Users" + chr(92) + "sample"))

    def test_install_paths_and_device_ids(self):
        for prefix in ("Applications", "opt/homebrew"):
            self.assertIn("fixed-tool-install-path", self.categories("/" + prefix + "/sample/bin"))
        self.assertIn("concrete-emulator-id", self.categories("emulator-" + "1234"))
        self.assertIn("concrete-adb-target", self.categories("adb -s " + "SYNTHETIC_DEVICE shell"))

    def test_fake_credentials(self):
        for fake in ("ghp_" + "x" * 30, "AKIA" + "X" * 16,
                     "-----BEGIN " + "PRIVATE KEY-----",
                     "https://" + "sample:dummy@example.invalid/",
                     "pass" + "word=" + repr("dummy" * 3)):
            with self.subTest(kind=fake[:4]):
                self.assertTrue(self.categories(fake))

    def test_portable_examples_and_public_identifiers(self):
        for safe in ("docs/android.md", "/path/to/Godot", "res://scripts/Battle.gd",
                     "user://synthetic.dat", "adb -s YOUR_DEVICE_SERIAL install -r example.apk",
                     'adb -s "$DEVICE_SERIAL" shell', "/usr/libexec/java_home",
                     "com.mwgames.dlz", "https://github.com/example/project",
                     'os.environ.get("GODOT_BIN")', 'password = secrets.token_urlsafe(24)'):
            with self.subTest(example=safe):
                self.assertEqual(self.categories(safe), set())

    def test_private_files_even_when_binary(self):
        for name in ("example.apk", "debug.keystore", ".env.local", "saves/synthetic.json",
                     "debug-signing.json"):
            self.assertTrue(gate.inspect(name, b"\0"))
        self.assertFalse(gate.inspect("extract/contracts/example.bin", b"\0"))
        self.assertFalse(gate.inspect(".env.example", b"GODOT_BIN=\n"))

    def test_scanner_output_does_not_echo_matched_values(self):
        fake = "ghp_" + "x" * 30
        output = io.StringIO()
        with patch.object(gate, "contents", return_value={"example.md": fake.encode()}), \
                patch("sys.argv", ["check_publication.py"]), redirect_stdout(output):
            self.assertEqual(gate.main(), 1)
        self.assertIn("example.md:1: known-token-format", output.getvalue())
        self.assertNotIn(fake, output.getvalue())

    def test_snapshot_staged_and_worktree_are_distinct(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(gate, "ROOT", Path(folder)):
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.DEVNULL)
            git("init", "-q")
            git("config", "user.name", "Synthetic Test")
            git("config", "user.email", "test@example.invalid")
            file = root / "example.md"
            file.write_text("emulator-" + "1234")
            git("add", "example.md")
            git("commit", "-qm", "synthetic baseline")
            file.write_text("portable")
            git("add", "example.md")
            file.write_text("working tree")
            (root / "new.md").write_text("new portable file")
            self.assertTrue(gate.inspect("example.md", gate.contents("commit", "HEAD")["example.md"]))
            self.assertEqual(gate.contents("staged", None), {"example.md": b"portable"})
            self.assertEqual(gate.contents("changed", "HEAD"),
                             {"example.md": b"working tree", "new.md": b"new portable file"})
            file.unlink()
            self.assertNotIn("example.md", gate.contents("changed", "HEAD"))


class ToolchainDiscoveryTest(unittest.TestCase):
    def test_godot_precedence_and_home_expansion(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = Path(folder) / "godot"
            tool.touch()
            with patch.dict(os.environ, {"GODOT_BIN": str(tool), "GODOT": "not-used"}, clear=True), \
                    patch.object(android, "execute", return_value=android.ENGINE_VERSION + ".stable.test"):
                self.assertEqual(android.detect_godot(None), tool.resolve())
                with patch.dict(os.environ, {"HOME": folder}):
                    self.assertEqual(android.detect_godot("~/godot"), tool.resolve())
                with self.assertRaises(RuntimeError):
                    android.detect_godot(str(Path(folder) / "missing"))

    def test_godot_path_lookup_and_missing_tool(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = Path(folder) / "godot"
            tool.touch()
            with patch.dict(os.environ, {}, clear=True), patch.object(android.shutil, "which", return_value=str(tool)), \
                    patch.object(android, "execute", return_value=android.ENGINE_VERSION + ".stable.test"):
                self.assertEqual(android.detect_godot(None), tool.resolve())
            with patch.dict(os.environ, {}, clear=True), patch.object(android.shutil, "which", return_value=None):
                with self.assertRaisesRegex(RuntimeError, "GODOT_BIN"):
                    android.detect_godot(None)

    def test_godot_version_guard(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = Path(folder) / "godot"
            tool.touch()
            with patch.object(android, "execute", return_value="0.0.invalid"):
                with self.assertRaises(RuntimeError):
                    android.detect_godot(str(tool))

    def test_java_explicit_and_path(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            (home / "bin").mkdir()
            for name in ("java", "keytool"):
                (home / "bin" / name).touch()
            self.assertEqual(android.detect_java(folder), home.resolve())
            with patch.dict(os.environ, {}, clear=True), patch.object(android.sys, "platform", "linux"), \
                    patch.object(android.shutil, "which", return_value=str(home / "bin/keytool")):
                self.assertEqual(android.detect_java(None), home.resolve())
            with self.assertRaises(RuntimeError):
                android.detect_java(str(home / "missing"))

    def test_macos_java_discovery(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            with patch.dict(os.environ, {}, clear=True), patch.object(android.sys, "platform", "darwin"), \
                    patch.object(Path, "is_file", return_value=True), \
                    patch.object(android.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, folder + "\n", "")):
                self.assertEqual(android.detect_java(None), home.resolve())

    def test_reports_hide_external_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            with patch.object(android, "ROOT", home):
                self.assertEqual(android.public_path(home / "out/example.apk"), "out/example.apk")
                external = home.parent / "external-output" / "example.apk"
                self.assertEqual(android.public_path(external), "<external>/example.apk")


if __name__ == "__main__":
    unittest.main()
