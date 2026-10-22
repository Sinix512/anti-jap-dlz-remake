#!/usr/bin/env python3
"""Verify the generated M5 media (MPEG/FLC/ANM) for the Godot remake.

Checks, without modifying anything:
  * all 33 MPEG WebMs/OGVs and all 4 FLC WebMs/OGVs exist, are non-empty,
    have duration > 0 and are 640x480;
  * m5_media.json covers every MPEG/FLC source and its durations/sizes/paths
    agree with the files on disk (both webm and ogv);
  * all 38 ANM raw copies + decoded previews exist, previews are 320x200 with
    duration > 0, and m5_anm.json says decoded=true with the right frame count;
  * audio is present in MPEG WebMs when the source has audio;
  * generated media stays under the 350 MiB budget.

Usage:
  python3 tools/verify_m5_media.py
  python3 tools/prepare_m5_media.py --verify
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = PROJECT_ROOT.parent / "dlz" / "ANTI-JAP"
DEFAULT_DEST = PROJECT_ROOT / "godot" / "assets" / "m5"
DEFAULT_DATA = PROJECT_ROOT / "godot" / "data"
DEFAULT_FFPROBE = Path(
    os.environ.get(
        "M5_FFPROBE", "ffprobe"
    )
)

EXPECTED_MPEG = 33
EXPECTED_FLC = 4
EXPECTED_ANM = 38
MEDIA_BUDGET = 350 * 1024 * 1024
ANM_RAW_BUDGET = 7 * 1024 * 1024
VARIANTS = {"D01A", "D07A", "D10A", "D14A", "D28A"}
FLC_NAMES = ["KINGSOFT", "KR-1", "TEST01", "TRAIN"]


def human(n: int | float) -> str:
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.1f} GiB"


def ratio(value):
    if not value or value in ("N/A", "0/0"):
        return None
    try:
        if ":" in value:
            a, b = value.split(":", 1)
            return float(a) / float(b) if float(b) else None
        if "/" in value:
            a, b = value.split("/", 1)
            return float(a) / float(b) if float(b) else None
        return float(value)
    except (ValueError, ZeroDivisionError):
        return None


def ffprobe(ffprobe_path: Path, path: Path) -> dict:
    cmd = [
        str(ffprobe_path),
        "-v",
        "error",
        "-show_entries",
        "format=duration,size,format_name",
        "-show_entries",
        "stream=codec_type,codec_name,width,height,channels,sample_rate,avg_frame_rate",
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or "ffprobe failed").strip()[:300])
    raw = json.loads(proc.stdout)
    fmt = raw.get("format", {})
    streams = raw.get("streams", [])
    v = next((s for s in streams if s.get("codec_type") == "video"), None)
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)
    return {
        "duration": float(fmt["duration"]) if fmt.get("duration") not in (None, "N/A") else 0.0,
        "size": int(fmt["size"]) if fmt.get("size") not in (None, "N/A") else path.stat().st_size,
        "width": int(v.get("width") or 0) if v else 0,
        "height": int(v.get("height") or 0) if v else 0,
        "video_codec": v.get("codec_name") if v else None,
        "audio_codec": a.get("codec_name") if a else None,
        "has_audio": a is not None,
        "fps": ratio(v.get("avg_frame_rate")) if v else None,
    }


def res_to_path(dest: Path, respath: str) -> Path | None:
    prefix = "res://assets/m5/"
    if not isinstance(respath, str) or not respath.startswith(prefix):
        return None
    return dest / respath[len(prefix) :]


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.checks = 0

    def check(self, cond: bool, msg: str) -> None:
        self.checks += 1
        if not cond:
            self.errors.append(msg)

    def warn(self, cond: bool, msg: str) -> None:
        self.checks += 1
        if not cond:
            self.warnings.append(msg)

    def fail(self, msg: str) -> None:
        self.errors.append(msg)


def verify_media(
    src: Path, dest: Path, data_dir: Path, ffprobe_path: Path, rep: Report
) -> dict:
    manifest_path = data_dir / "m5_media.json"
    if not manifest_path.is_file():
        rep.fail(f"missing {manifest_path}")
        return {}
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        rep.fail(f"cannot read {manifest_path}: {exc}")
        return {}
    clips = manifest.get("clips")
    if not isinstance(clips, list):
        rep.fail("m5_media.json: clips is not a list")
        return manifest
    rep.check(manifest.get("schema") == 1, "m5_media.json: schema != 1")
    rep.check(
        manifest.get("viewport", {}).get("width") == 640
        and manifest.get("viewport", {}).get("height") == 480,
        "m5_media.json: viewport is not 640x480",
    )

    by_source: dict[str, dict] = {}
    for clip in clips:
        source = clip.get("source")
        if not isinstance(source, str):
            rep.fail("m5_media.json: clip without source")
            continue
        if source in by_source:
            rep.fail(f"m5_media.json: duplicate source {source}")
        by_source[source] = clip

    mpeg_sources = sorted(
        {p.name for p in (src / "MPEG").glob("*.MPG")}
        | {p.name for p in (src / "MPEG").glob("*.mpg")}
    )
    expected_media_sources = {f"MPEG/{name}" for name in mpeg_sources}
    expected_media_sources |= {f"{name}.FLC" for name in FLC_NAMES}
    rep.check(
        len(mpeg_sources) == EXPECTED_MPEG,
        f"source MPEG count is {len(mpeg_sources)}, expected {EXPECTED_MPEG}",
    )
    missing_sources = sorted(expected_media_sources - set(by_source))
    rep.check(not missing_sources, f"m5_media.json missing sources: {missing_sources[:8]}")
    extra_sources = sorted(set(by_source) - expected_media_sources)
    rep.check(not extra_sources, f"m5_media.json has unknown sources: {extra_sources[:8]}")

    rep.check(
        manifest.get("counts", {}).get("mpeg") == EXPECTED_MPEG,
        f"m5_media.json mpeg count {manifest.get('counts', {}).get('mpeg')} != {EXPECTED_MPEG}",
    )
    rep.check(
        manifest.get("counts", {}).get("flc") == EXPECTED_FLC,
        f"m5_media.json flc count {manifest.get('counts', {}).get('flc')} != {EXPECTED_FLC}",
    )
    rep.check(
        manifest.get("counts", {}).get("total") == EXPECTED_MPEG + EXPECTED_FLC,
        "m5_media.json total count is not 37",
    )

    by_source_map = manifest.get("by_source", {})
    rep.check(
        isinstance(by_source_map, dict) and len(by_source_map) == EXPECTED_MPEG + EXPECTED_FLC,
        "m5_media.json by_source does not cover 37 clips",
    )
    by_source_ogv = manifest.get("by_source_ogv", {})
    rep.check(
        isinstance(by_source_ogv, dict)
        and len(by_source_ogv) == EXPECTED_MPEG + EXPECTED_FLC,
        "m5_media.json by_source_ogv does not cover 37 clips",
    )
    rep.check(
        manifest.get("godot_playback") == "ogv",
        "m5_media.json godot_playback is not ogv",
    )

    media_bytes = 0
    duration_total = 0.0
    ogv_duration_total = 0.0
    checked = 0
    ogv_checked = 0
    for source in sorted(expected_media_sources):
        clip = by_source.get(source)
        if not clip:
            continue
        kind = clip.get("kind")
        expected_kind = "flc" if source.endswith(".FLC") else "mpeg"
        rep.check(kind == expected_kind, f"{source}: kind {kind!r} != {expected_kind!r}")
        path = res_to_path(dest, clip.get("path", ""))
        if path is None:
            rep.fail(f"{source}: bad res path {clip.get('path')!r}")
            continue
        if not path.is_file():
            rep.fail(f"{source}: missing generated file {path}")
            continue
        size = path.stat().st_size
        rep.check(size > 0, f"{source}: generated file is empty")
        media_bytes += size
        try:
            info = ffprobe(ffprobe_path, path)
        except Exception as exc:
            rep.fail(f"{source}: ffprobe failed: {exc}")
            continue
        checked += 1
        duration_total += info["duration"]
        rep.check(info["duration"] > 0, f"{source}: WebM duration is 0")
        rep.check(
            (info["width"], info["height"]) == (640, 480),
            f"{source}: WebM is {info['width']}x{info['height']}, expected 640x480",
        )
        rep.check(
            info["video_codec"] in ("vp9", "vp8"),
            f"{source}: unexpected video codec {info['video_codec']}",
        )
        ogv_path = res_to_path(dest, clip.get("ogv_path", ""))
        if ogv_path is None:
            rep.fail(f"{source}: bad ogv path {clip.get('ogv_path')!r}")
        elif not ogv_path.is_file():
            rep.fail(f"{source}: missing playback OGV {ogv_path}")
        else:
            ogv_size = ogv_path.stat().st_size
            rep.check(ogv_size > 0, f"{source}: OGV is empty")
            media_bytes += ogv_size
            rep.check(
                ogv_path.name == ogv_path.name.lower(),
                f"{source}: OGV filename is not lowercase: {ogv_path.name}",
            )
            try:
                ogv_info = ffprobe(ffprobe_path, ogv_path)
            except Exception as exc:
                rep.fail(f"{source}: OGV ffprobe failed: {exc}")
                ogv_info = None
            if ogv_info:
                ogv_checked += 1
                ogv_duration_total += ogv_info["duration"]
                rep.check(ogv_info["duration"] > 0, f"{source}: OGV duration is 0")
                rep.check(
                    (ogv_info["width"], ogv_info["height"]) == (640, 480),
                    f"{source}: OGV is {ogv_info['width']}x{ogv_info['height']}, "
                    "expected 640x480",
                )
                rep.check(
                    ogv_info["video_codec"] == "theora",
                    f"{source}: OGV video codec {ogv_info['video_codec']} != theora",
                )
                rep.check(
                    ogv_info["fps"] is None or ogv_info["fps"] <= 12.1,
                    f"{source}: OGV fps {ogv_info['fps']} exceeds 12",
                )
                rep.check(
                    abs(float(clip.get("ogv_duration", -1)) - ogv_info["duration"]) < 0.11,
                    f"{source}: manifest ogv_duration {clip.get('ogv_duration')} "
                    f"!= file {ogv_info['duration']}",
                )
                rep.check(
                    int(clip.get("ogv_size_bytes", -1)) == ogv_size,
                    f"{source}: manifest ogv_size_bytes mismatch",
                )
        rep.check(
            clip.get("width") == 640 and clip.get("height") == 480,
            f"{source}: manifest dimensions are not 640x480",
        )
        rep.check(
            abs(float(clip.get("duration", -1)) - info["duration"]) < 0.11,
            f"{source}: manifest duration {clip.get('duration')} != file {info['duration']}",
        )
        rep.check(
            int(clip.get("size_bytes", -1)) == size,
            f"{source}: manifest size {clip.get('size_bytes')} != file {size}",
        )
        rep.check(
            path.name == path.name.lower(),
            f"{source}: generated filename is not lowercase: {path.name}",
        )
        src_path = src / source
        rep.check(src_path.is_file(), f"{source}: original source is missing")
        if src_path.is_file():
            rep.check(
                int(clip.get("source_size_bytes", -1)) == src_path.stat().st_size,
                f"{source}: source_size_bytes mismatch",
            )
        if expected_kind == "mpeg":
            try:
                src_info = ffprobe(ffprobe_path, src_path)
            except Exception as exc:
                rep.warn(False, f"{source}: source ffprobe failed: {exc}")
                src_info = {}
            if src_info.get("has_audio"):
                rep.check(info["has_audio"], f"{source}: source audio is missing from WebM")
                rep.check(clip.get("has_audio") is True, f"{source}: manifest has_audio != true")
            rep.check(
                clip.get("level_index")
                == int(re.match(r"d(\d+)", clip.get("id", "")).group(1)) - 1,
                f"{source}: level_index does not match Dxx-1",
            )
            is_variant = path.name in {f"{v.lower()}.webm" for v in VARIANTS}
            rep.check(
                bool(clip.get("variant")) == is_variant,
                f"{source}: variant flag is wrong",
            )
            if is_variant:
                rep.check(
                    isinstance(clip.get("variant_of"), str)
                    and clip["variant_of"] == path.stem[:-1],
                    f"{source}: variant_of is wrong",
                )
        else:
            rep.check(clip.get("level_index") is None, f"{source}: FLC must not have level_index")
            rep.check(not clip.get("variant"), f"{source}: FLC must not be a variant")

    rep.check(
        checked == EXPECTED_MPEG + EXPECTED_FLC,
        f"checked {checked} MPEG/FLC WebMs, expected {EXPECTED_MPEG + EXPECTED_FLC}",
    )
    rep.check(
        ogv_checked == EXPECTED_MPEG + EXPECTED_FLC,
        f"checked {ogv_checked} MPEG/FLC OGVs, expected {EXPECTED_MPEG + EXPECTED_FLC}",
    )
    return {
        "manifest": manifest,
        "media_bytes": media_bytes,
        "duration_total": duration_total,
        "ogv_duration_total": ogv_duration_total,
        "checked": checked,
        "ogv_checked": ogv_checked,
    }


def verify_anm(src: Path, dest: Path, data_dir: Path, ffprobe_path: Path, rep: Report) -> dict:
    manifest_path = data_dir / "m5_anm.json"
    if not manifest_path.is_file():
        rep.fail(f"missing {manifest_path}")
        return {}
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        rep.fail(f"cannot read {manifest_path}: {exc}")
        return {}
    files = manifest.get("files")
    if not isinstance(files, list):
        rep.fail("m5_anm.json: files is not a list")
        return manifest
    rep.check(manifest.get("schema") == 1, "m5_anm.json: schema != 1")

    src_anms = sorted(src.glob("*.ANM"), key=lambda p: p.name.lower())
    rep.check(
        len(src_anms) == EXPECTED_ANM,
        f"source ANM count is {len(src_anms)}, expected {EXPECTED_ANM}",
    )
    by_source = {f.get("source"): f for f in files}
    expected = {p.name for p in src_anms}
    rep.check(
        len(by_source) == EXPECTED_ANM,
        f"m5_anm.json has {len(by_source)} entries, expected {EXPECTED_ANM}",
    )
    missing = sorted(expected - set(by_source))
    extra = sorted(set(by_source) - expected)
    rep.check(not missing, f"m5_anm.json missing ANM entries: {missing[:8]}")
    rep.check(not extra, f"m5_anm.json has unknown ANM entries: {extra[:8]}")
    rep.check(
        manifest.get("summary", {}).get("decoded") == EXPECTED_ANM,
        f"m5_anm.json decoded count {manifest.get('summary', {}).get('decoded')} != {EXPECTED_ANM}",
    )
    raw_info = manifest.get("raw", {})
    rep.check(raw_info.get("copied") is True, "m5_anm.json: raw ANM copies are not marked copied")
    rep.check(
        int(raw_info.get("total_bytes", 0)) < ANM_RAW_BUDGET,
        f"raw ANM total {raw_info.get('total_bytes')} exceeds 7 MiB",
    )

    decoded_count = 0
    frames_total = 0
    raw_bytes = 0
    anm_media_bytes = 0
    for source in sorted(expected):
        entry = by_source.get(source)
        if not entry:
            continue
        rep.check(entry.get("decoded") is True, f"{source}: decoded is not true")
        header = entry.get("header", {})
        rep.check(header.get("width") == 320, f"{source}: header width != 320")
        rep.check(header.get("height") == 200, f"{source}: header height != 200")
        frames = int(header.get("frames") or 0)
        rep.check(frames > 0, f"{source}: header frame count is 0")
        decode = entry.get("decode", {})
        rep.check(decode.get("decoded") is True, f"{source}: decode.decoded is not true")
        if entry.get("decoded") is not True:
            continue
        decoded_count += 1
        frames_total += frames
        webm = res_to_path(dest, decode.get("webm_path", ""))
        raw = res_to_path(dest, entry.get("raw_path", ""))
        if webm is None or not webm.is_file():
            rep.fail(f"{source}: missing decoded WebM {decode.get('webm_path')}")
            continue
        if raw is None or not raw.is_file():
            rep.fail(f"{source}: missing raw ANM {entry.get('raw_path')}")
        else:
            raw_bytes += raw.stat().st_size
            src_path = src / source
            rep.check(
                raw.stat().st_size == src_path.stat().st_size,
                f"{source}: raw copy size mismatch",
            )
        size = webm.stat().st_size
        rep.check(size > 0, f"{source}: decoded WebM is empty")
        anm_media_bytes += size
        try:
            info = ffprobe(ffprobe_path, webm)
        except Exception as exc:
            rep.fail(f"{source}: ffprobe failed: {exc}")
            continue
        rep.check(info["duration"] > 0, f"{source}: decoded WebM duration is 0")
        rep.check(
            (info["width"], info["height"]) == (320, 200),
            f"{source}: decoded WebM is {info['width']}x{info['height']}, expected 320x200",
        )
        rep.check(
            abs(info["duration"] - frames / 12.0) < 0.2,
            f"{source}: WebM duration {info['duration']:.3f} != frames/12 {frames / 12.0:.3f}",
        )
        rep.check(
            int(decode.get("size_bytes", -1)) == size,
            f"{source}: manifest preview size mismatch",
        )
    rep.check(
        decoded_count == EXPECTED_ANM,
        f"decoded {decoded_count} ANM previews, expected {EXPECTED_ANM}",
    )
    rep.check(
        frames_total == int(manifest.get("summary", {}).get("frames_decoded", -1)),
        f"m5_anm.json frame total {manifest.get('summary', {}).get('frames_decoded')} "
        f"!= per-file total {frames_total}",
    )
    rep.check(
        raw_bytes == int(raw_info.get("total_bytes", -1)),
        f"raw ANM bytes {raw_bytes} != manifest {raw_info.get('total_bytes')}",
    )
    return {
        "manifest": manifest,
        "decoded": decoded_count,
        "frames": frames_total,
        "raw_bytes": raw_bytes,
        "media_bytes": anm_media_bytes,
    }


def run_verification(
    src: Path,
    dest: Path,
    data_dir: Path,
    ffprobe: Path,
    budget: int = MEDIA_BUDGET,
) -> int:
    rep = Report()
    print("M5 media verification")
    print(f"  source : {src}")
    print(f"  output : {dest}")
    print(f"  ffprobe: {ffprobe}")
    if not src.is_dir():
        print(f"FAIL: source directory not found: {src}", file=sys.stderr)
        return 1
    if not dest.is_dir():
        print(f"FAIL: output directory not found: {dest}", file=sys.stderr)
        return 1
    media = verify_media(src, dest, data_dir, ffprobe, rep)
    anm = verify_anm(src, dest, data_dir, ffprobe, rep)

    media_bytes = sum(p.stat().st_size for p in dest.rglob("*") if p.is_file())
    rep.check(media_bytes > 0, "generated media directory is empty")
    rep.check(
        media_bytes <= budget,
        f"generated media {human(media_bytes)} exceeds budget {human(budget)}",
    )
    media_ok = (
        media.get("checked", 0) == EXPECTED_MPEG + EXPECTED_FLC
        and media.get("ogv_checked", 0) == EXPECTED_MPEG + EXPECTED_FLC
    )
    anm_ok = anm.get("decoded", 0) == EXPECTED_ANM

    print()
    if media_ok and not rep.errors:
        print(
            f"  MPEG/FLC : {media.get('checked')} WebMs + {media.get('ogv_checked')} OGVs, "
            f"{human(media.get('media_bytes', 0))}, "
            f"{media.get('duration_total', 0):.1f}s total"
        )
    else:
        print(f"  MPEG/FLC : {media.get('checked', 0)}/37 WebMs checked")
    if anm_ok:
        print(
            f"  ANM      : {anm.get('decoded')} decoded, {anm.get('frames')} frames, "
            f"{human(anm.get('media_bytes', 0))} previews, {human(anm.get('raw_bytes', 0))} raw"
        )
    else:
        print(f"  ANM      : {anm.get('decoded', 0)}/38 decoded")
    print(f"  total    : {human(media_bytes)} (budget {human(budget)})")
    print(f"  checks   : {rep.checks} ({len(rep.errors)} failed)")

    if rep.warnings:
        print("  warnings:")
        for w in rep.warnings[:20]:
            print(f"    - {w}")
        if len(rep.warnings) > 20:
            print(f"    ... and {len(rep.warnings) - 20} more")
    if rep.errors:
        print("  failures:")
        for e in rep.errors[:40]:
            print(f"    - {e}")
        if len(rep.errors) > 40:
            print(f"    ... and {len(rep.errors) - 40} more")
        print("RESULT: FAIL")
        return 1
    print("RESULT: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify generated M5 media.")
    parser.add_argument("--src", default=str(DEFAULT_SRC), help="original ANTI-JAP directory")
    parser.add_argument("--dest", default=str(DEFAULT_DEST), help="generated media directory")
    parser.add_argument("--data", default=str(DEFAULT_DATA), help="manifest directory")
    parser.add_argument("--ffprobe", default=str(DEFAULT_FFPROBE), help="ffprobe executable")
    parser.add_argument(
        "--budget-mb", type=int, default=350, help="generated media budget in MiB"
    )
    args = parser.parse_args(argv)
    return run_verification(
        src=Path(args.src).resolve(),
        dest=Path(args.dest).resolve(),
        data_dir=Path(args.data).resolve(),
        ffprobe=Path(args.ffprobe),
        budget=args.budget_mb * 1024 * 1024,
    )


if __name__ == "__main__":
    raise SystemExit(main())
