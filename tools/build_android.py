#!/usr/bin/env python3
"""Build and audit the offline Android debug APK, without changing user editor settings.

Requires Godot 4.7.2 + matching official Android export template, Android SDK 36
and a JDK (17+). Generated portable-editor config, signing key and APK stay in out/.
No device install, game launch, campaign execution or player-save access occurs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot"
OUT = ROOT / "out/android"
ENGINE_VERSION = "4.7.2"
PACKAGE_ID = "com.mwgames.dlz"


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def execute(args: list[str], *, env: dict | None = None, log: Path | None = None,
            timeout: int = 600) -> str:
    result = subprocess.run([str(x) for x in args], cwd=ROOT, env=env,
                            capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    if log:
        log.write_text(output)
    require(result.returncode == 0, f"Command failed ({result.returncode}): {args[0]}\n{output[-8000:]}")
    return output


def detect_godot(explicit: str | None) -> Path:
    value = explicit or os.environ.get("GODOT_BIN") or os.environ.get("GODOT") or shutil.which("godot")
    require(bool(value), "Use --godot, GODOT_BIN/GODOT, or put godot on PATH")
    path = Path(shutil.which(value) or value).expanduser().resolve()
    require(path.is_file(), "Godot executable not found; check --godot or GODOT_BIN/GODOT")
    version = execute([path, "--version"]).strip()
    require(version.startswith(ENGINE_VERSION + ".stable."), f"Expected {ENGINE_VERSION}.stable, found {version}")
    return path


def detect_java(explicit: str | None) -> Path:
    value = explicit or os.environ.get("JAVA_HOME")
    if value:
        path = Path(value).expanduser().resolve()
        require((path / "bin/keytool").is_file() and (path / "bin/java").is_file(),
                "Invalid --java-home/JAVA_HOME; use a JDK with bin/java and bin/keytool")
        return path
    candidates = []
    # Resolve the active JDK, not one developer's Homebrew installation.
    if sys.platform == "darwin" and Path("/usr/libexec/java_home").is_file():
        result = subprocess.run(["/usr/libexec/java_home"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout.strip():
            candidates.append(result.stdout.strip())
    keytool = shutil.which("keytool")
    if keytool:
        candidates.append(str(Path(keytool).resolve().parent.parent))
    for candidate in candidates:
        if (Path(candidate) / "bin/keytool").is_file() and (Path(candidate) / "bin/java").is_file():
            return Path(candidate).resolve()
    raise RuntimeError("Set JAVA_HOME to a JDK installation (with bin/java and bin/keytool)")


def detect_sdk(explicit: str | None) -> Path:
    value = explicit or os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not value:
        value = str(Path.home() / ("Library/Android/sdk" if sys.platform == "darwin" else "Android/Sdk"))
    path = Path(value).expanduser().resolve()
    require((path / "platform-tools/adb").is_file(), f"Android SDK platform-tools missing: {path}")
    require((path / "platforms/android-36/android.jar").is_file(), "Install Android SDK platform android-36")
    return path


def template_path(explicit: str | None) -> Path:
    if explicit:
        result = Path(explicit).expanduser().resolve()
    else:
        base = (Path.home() / "Library/Application Support/Godot" if sys.platform == "darwin"
                else Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot")
        result = base / f"export_templates/{ENGINE_VERSION}.stable/android_debug.apk"
    require(result.is_file() and zipfile.is_zipfile(result),
            f"Missing matching official Android debug template: {result}\n"
            "Install Godot 4.7.2 export templates using Editor > Manage Export Templates, or pass --template.")
    return result


def prepare_editor(godot: Path, template: Path, java: Path, sdk: Path) -> tuple[Path, dict]:
    """A copied self-contained editor isolates SDK paths and generated signing credentials."""
    portable = OUT / "toolchain/editor"
    portable.mkdir(parents=True, exist_ok=True)
    binary = portable / ("Godot.exe" if os.name == "nt" else "Godot")
    original_fingerprint = sha256(godot)
    marker = portable / "source-engine.sha256"
    if not binary.is_file() or not marker.exists() or marker.read_text().strip() != original_fingerprint:
        shutil.copy2(godot, binary)
        # A macOS universal executable copied outside its signed app bundle needs
        # a fresh ad-hoc signature. This only changes our disposable copy.
        if sys.platform == "darwin":
            execute(["codesign", "--force", "--sign", "-", binary])
        marker.write_text(original_fingerprint + "\n")
    (portable / "_sc_").touch()
    data = portable / "editor_data"
    data.mkdir(exist_ok=True)
    target = data / f"export_templates/{ENGINE_VERSION}.stable"
    target.mkdir(parents=True, exist_ok=True)
    installed = target / "android_debug.apk"
    if not installed.exists() or sha256(installed) != sha256(template):
        shutil.copy2(template, installed)
    (target / "version.txt").write_text(f"{ENGINE_VERSION}.stable\n")
    settings = data / "editor_settings-4.7.tres"
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
                        'interface/editor/localization/editor_language = "en"\n'
                        f'export/android/java_sdk_path = {json.dumps(str(java))}\n'
                        f'export/android/android_sdk_path = {json.dumps(str(sdk))}\n')
    key = OUT / "toolchain/debug.keystore"
    credentials = OUT / "toolchain/debug-signing.json"
    require(key.exists() == credentials.exists(), "Debug key/credential pair incomplete; restore both or use another out directory")
    if not key.exists():
        password = secrets.token_urlsafe(24)
        credentials.write_text(json.dumps({"alias": "dlzdebug", "password": password}) + "\n")
        credentials.chmod(0o600)
        signing = json.loads(credentials.read_text())
        env = dict(os.environ, DLZ_DEBUG_KEY_PASSWORD=signing["password"])
        execute([java / "bin/keytool", "-genkeypair", "-noprompt", "-keystore", key,
                 "-alias", signing["alias"], "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                 "-dname", "CN=DLZ Local Debug,OU=Development,O=MW Games,C=CN",
                 "-storepass:env", "DLZ_DEBUG_KEY_PASSWORD", "-keypass:env", "DLZ_DEBUG_KEY_PASSWORD"], env=env)
        key.chmod(0o600)
    signing = json.loads(credentials.read_text())
    env = dict(os.environ, JAVA_HOME=str(java), ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk),
               GODOT_ANDROID_KEYSTORE_DEBUG_PATH=str(key), GODOT_ANDROID_KEYSTORE_DEBUG_USER=signing["alias"],
               GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=signing["password"])
    env["PATH"] = str(java / "bin") + os.pathsep + env.get("PATH", "")
    return binary, env


def source_fingerprints() -> dict[str, str]:
    files = [PROJECT / "project.godot", PROJECT / "export_presets.cfg", PROJECT / "Main.tscn",
             ROOT / "tools/build_android.py"]
    if (PROJECT / "android_icon.svg").exists():
        files.append(PROJECT / "android_icon.svg")
    files += sorted((PROJECT / "scripts").rglob("*.gd"))
    files += sorted((PROJECT / "data").glob("*.json"))
    # Ignore editor-generated .import sidecars, but freeze all shipped source
    # media as well as scripts/data while the exporter reads them.
    files += sorted(p for p in (PROJECT / "assets").rglob("*") if p.is_file()
                    and p.suffix.lower() in {".png", ".wav", ".ogg", ".ogv", ".bin", ".json", ".fnt"})
    return {str(p.relative_to(ROOT)): sha256(p) for p in files}


def public_path(path: Path) -> str:
    """Reports expose repository-relative paths, never a user's home/mount path."""
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return "<external>/" + resolved.name


def audit_apk(apk: Path, sdk: Path, java: Path) -> dict:
    versions = sorted((sdk / "build-tools").iterdir(), key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.name)))
    tools = next((p for p in reversed(versions) if (p / "aapt").is_file() and (p / "apksigner").is_file()), None)
    require(tools is not None, "Android SDK build-tools with aapt and apksigner are required")
    badging = execute([tools / "aapt", "dump", "badging", apk])
    permissions = execute([tools / "aapt", "dump", "permissions", apk])
    manifest = execute([tools / "aapt", "dump", "xmltree", apk, "AndroidManifest.xml"])
    signature = execute([tools / "apksigner", "verify", "--verbose", "--print-certs", apk],
                        env=dict(os.environ, JAVA_HOME=str(java)))
    (OUT / "aapt-badging.txt").write_text(badging)
    (OUT / "aapt-permissions.txt").write_text(permissions)
    (OUT / "AndroidManifest.txt").write_text(manifest)
    (OUT / "apksigner.txt").write_text(signature)
    require(f"package: name='{PACKAGE_ID}'" in badging, "Unexpected Android application ID")
    require("sdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging, "Expected minSdk24 / targetSdk36")
    require("native-code: 'arm64-v8a'" in badging, "APK must contain arm64-v8a")
    # Godot 4.7 exposes a launcher alias; aapt badging omits activity-alias entries.
    require('"com.godot.game.GodotAppLauncher"' in manifest
            and '"com.godot.game.GodotApp"' in manifest
            and '"android.intent.action.MAIN"' in manifest
            and '"android.intent.category.LAUNCHER"' in manifest, "Android launcher alias missing")
    require("application-debuggable" in badging, "This build is intentionally a debug build, not a production release")
    require('android:screenOrientation' in manifest and re.search(r'android:screenOrientation.*\)0x0\b', manifest),
            "Android activity must be landscape")
    requested = re.findall(r"uses-permission(?:-sdk-\d+)?: name='([^']+)'", permissions)
    sensitive = [p for p in requested if p not in ("android.permission.VIBRATE",)]
    require(not sensitive, "Unexpected permissions: " + ", ".join(sensitive))
    with zipfile.ZipFile(apk) as archive:
        files = set(archive.namelist())
        require(not any(p.startswith("assets/tests/") for p in files), "Developer tests leaked into APK")
        require(not any(p.endswith((".webm", ".anm")) for p in files), "Unused source media leaked into APK")
        m4 = json.loads(archive.read("assets/data/m4.json"))
        require(len(m4["levels"]) == 47, "APK must include all 47 mission definitions")
        require("lib/arm64-v8a/libgodot_android.so" in files, "Godot ARM64 engine missing")
        require("assets/project.binary" in files, "Exported project configuration missing")
        def has_resource(path: str) -> bool:
            p = "assets/" + path.removeprefix("res://")
            if p in files:
                return True
            for suffix in (".remap", ".import"):
                if p + suffix in files:
                    remap = archive.read(p + suffix).decode()
                    found = re.search(r'path="res://([^\"]+)"', remap)
                    if found and "assets/" + found[1] in files:
                        return True
            return False
        required = {"res://Main.tscn", "res://scripts/Main.gd", "res://scripts/Battle.gd",
                    "res://scripts/ui/TouchInput.gd", "res://assets/font/hzk16.fnt"}
        for name in files:
            if name.startswith("assets/data/") and name.endswith(".json"):
                text = archive.read(name).decode()
                for path in re.findall(r'"(res://[^"\\]+)"', text):
                    # m5_anm raw_path records provenance only. Playback uses
                    # imported sheets/Theora, never the original ANM bytes.
                    if Path(path).suffix and not path.endswith(".anm"):
                        required.add(path.replace(".webm", ".ogv"))
        missing = sorted(path for path in required if not has_resource(path))
        require(not missing, "Runtime resources missing from APK: " + ", ".join(missing[:25]))
        report = {"package_id": PACKAGE_ID, "launch_activity": "com.godot.game.GodotAppLauncher",
                  "target_activity": "com.godot.game.GodotApp",
                  "build_type": "debug", "min_sdk": 24, "target_sdk": 36, "orientation": "landscape",
                  "abis": ["arm64-v8a"], "requested_permissions": requested,
                  "mission_definitions": len(m4["levels"]), "audited_runtime_paths": len(required),
                  "missing_runtime_paths": missing, "apk_entries": len(files),
                  "developer_tests_included": False, "signature_verified": True,
                  "signer_certificate_sha256": re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]+)", signature)[1]}
    report.update({"apk": public_path(apk), "bytes": apk.stat().st_size, "sha256": sha256(apk)})
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot 4.7.2 editor executable (or GODOT_BIN/GODOT/PATH)")
    parser.add_argument("--sdk", help="Android SDK root (or ANDROID_HOME)")
    parser.add_argument("--java-home", help="JDK home (or JAVA_HOME)")
    parser.add_argument("--template", help="Matching official Android debug template APK")
    parser.add_argument("--output", type=Path, default=OUT / "dlz-android-debug.apk")
    parser.add_argument("--verify-only", type=Path, metavar="APK", help="Audit an existing APK without rebuilding")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    java = detect_java(args.java_home)
    sdk = detect_sdk(args.sdk)
    if args.verify_only:
        report = audit_apk(args.verify_only.resolve(), sdk, java)
    else:
        godot = detect_godot(args.godot)
        template = template_path(args.template)
        binary, env = prepare_editor(godot, template, java, sdk)
        snapshot = source_fingerprints()
        require((PROJECT / "scripts/ui/TouchInput.gd").is_file(), "Touch adaptation has not been integrated yet")
        apk = args.output.resolve()
        apk.parent.mkdir(parents=True, exist_ok=True)
        staging = OUT / "staging"
        staging.mkdir(exist_ok=True)
        staged_apk = staging / apk.name
        # The CLI deliberately does not enable remote debugging or deploy to a device.
        # Publish the output only after validation, so a failed export never replaces it.
        log = execute([binary, "--headless", "--path", PROJECT,
                       "--log-file", OUT / "godot-export.log", "--export-debug", "Android", staged_apk],
                      env=env, log=OUT / "export-stdout.log", timeout=900)
        require(not any(x in log for x in ("SCRIPT ERROR:", "Parse Error:", "Failed to export project")),
                "Godot reported a script/export error; see out/android/export-stdout.log")
        require(snapshot == source_fingerprints(), "Source files changed during export; rebuild after integration is stable")
        report = audit_apk(staged_apk, sdk, java)
        os.replace(staged_apk, apk)
        report["apk"] = public_path(apk)
        report.update({"godot_version": execute([godot, "--version"]).strip(),
                       "template_sha256": sha256(template), "source_sha256": snapshot,
                       "git_head": execute(["git", "rev-parse", "HEAD"]).strip(),
                       "git_status": execute(["git", "status", "--porcelain"]).splitlines(),
                       "user_editor_settings_modified": False, "device_installed": False})
    report_path = OUT / ("verification-report.json" if args.verify_only else "build-report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("source_sha256", "git_status")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired, OSError, zipfile.BadZipFile) as error:
        print("ANDROID BUILD FAILED:", error, file=sys.stderr)
        raise SystemExit(1)
