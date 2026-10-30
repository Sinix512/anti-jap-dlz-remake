#!/usr/bin/env python3
"""Heuristic publication gate; reports locations/categories, never secret values."""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    "personal-or-temporary-path": r"/(?:Users|home|Volumes|private/tmp|tmp)/[^\s\"'<>]+",
    "windows-personal-path": r"\b[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/][^\s\"'<>]+",
    "fixed-tool-install-path": r"/(?:Applications|opt/homebrew)/[^\s\"'<>]+",
    "concrete-emulator-id": r"\bemulator-\d+\b",
    "concrete-adb-target": r"\badb\s+-s\s+(?!YOUR_DEVICE_SERIAL\b|[<$\"'])[^\s]+",
    "private-key": r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "known-token-format": r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b",
    "url-credentials": r"https?://[^\s/@:]+:[^\s/@]+@",
    "literal-credential": r'''(?i)["']?(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)["']?\s*[:=]\s*["'][^\s"']{8,}["']''',
}
PATTERNS = {name: re.compile(pattern) for name, pattern in RULES.items()}
PRIVATE_EXTENSIONS = {".apk", ".aab", ".keystore", ".jks", ".key", ".pem", ".p12", ".pfx"}


def inspect(path: str, data: bytes) -> list[tuple[str, int, str]]:
    findings = []
    file = PurePosixPath(path)
    if (file.suffix.lower() in PRIVATE_EXTENSIONS
            or (file.name.startswith(".env") and file.name != ".env.example")
            or any(part in {"saves", "user_data"} for part in file.parts)
            or file.name == "debug-signing.json"):
        findings.append((path, 0, "private-or-generated-file"))
    if b"\0" in data:  # Binary assets still require manual metadata/visual review.
        return findings
    for line_number, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
        for category, pattern in PATTERNS.items():
            if pattern.search(line):
                findings.append((path, line_number, category))
    return findings


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT, stderr=subprocess.PIPE)


def names(data: bytes) -> list[str]:
    return [part.decode("utf-8") for part in data.split(b"\0") if part]


def contents(mode: str, ref: str | None) -> dict[str, bytes]:
    if mode == "commit":
        commit = git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
        paths = names(git("diff-tree", "--root", "--no-commit-id", "-r", "--name-only",
                          "--diff-filter=ACMRT", "-z", commit))
        return {path: git("show", f"{commit}:{path}") for path in paths}
    if mode == "changed":
        base = git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
        paths = set(names(git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, "--")))
        paths.update(names(git("ls-files", "--others", "--exclude-standard", "-z")))
        result = {}
        for path in sorted(paths):
            target = ROOT / path
            # Do not follow a newly added symlink outside the checkout.
            if target.is_symlink():
                import os
                result[path] = os.readlink(target).encode()
            elif target.is_file():
                result[path] = target.read_bytes()
        return result
    paths = names(git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z"))
    return {path: git("show", f":{path}") for path in paths}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--commit", metavar="REF", help="Scan changed files in a historical commit snapshot")
    group.add_argument("--changed-from", metavar="REF", help="Scan current changed/new files against a base")
    group.add_argument("--staged", action="store_true", help="Scan staged blobs (default)")
    args = parser.parse_args()
    mode, ref = ("commit", args.commit) if args.commit else ("changed", args.changed_from) if args.changed_from else ("staged", None)
    try:
        files = contents(mode, ref)
    except (subprocess.CalledProcessError, OSError, UnicodeError):
        parser.error("Cannot read scan target; check the Git ref and repository state")
    findings = [finding for path, blob in files.items() for finding in inspect(path, blob)]
    for path, line, category in findings:
        print(f"{path}:{line}: {category}")
    print(f"{'FAIL' if findings else 'PASS'}: {len(files)} files, {len(findings)} findings ({mode}); manual review still required")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
