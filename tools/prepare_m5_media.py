#!/usr/bin/env python3
"""Prepare M5 media for the Godot 4.7.2 remake of 抗日：地雷战.

Read-only source: ../dlz/ANTI-JAP/
Generated output (gitignored):
  godot/assets/m5/video/*.webm          33 MPEG -> 640x480 VP9/Vorbis (deliverable)
  godot/assets/m5/video/*.ogv           33 MPEG -> 640x480 Theora/Vorbis (Godot 4.7.2)
  godot/assets/m5/flc/*.webm             4 FLC  -> 640x480 max, <=12 fps
  godot/assets/m5/flc/*.ogv              4 FLC  -> Theora playback copies
  godot/assets/m5/anm/*.webm            38 ANM  -> 320x200 decoded preview
  godot/assets/m5/anm/*.anm             raw ANM copies (only while total < 7 MiB)
  godot/data/m5_media.json              MPEG/FLC manifest
  godot/data/m5_anm.json                ANM format facts + decode manifest

ANM container facts established from the original bytes (no guessing):
  0x000  "LPF " magic
  0x004  uint16 max pages (0x0100)
  0x006  uint16 pages used
  0x008  uint32 records
  0x00e  uint16 page-table offset (0x0500; 256 reserved 6-byte entries)
  0x010  "ANIM"
  0x014  uint16 width (320), 0x016 uint16 height (200)
  0x019  uint8  rate byte (0 in all 38 files)
  0x040  uint32 frames
  0x100  256 * 4-byte BGR0 palette
  0xb00  page data; each page starts with
           uint16 base_record, uint16 nb_records,
           uint16 total_record_bytes, uint16 pad,
           then nb_records * uint16 record sizes, then records,
           page stride 0x10000
  record  starts with 42 00 01 00, then the RLE command stream:
           0x01..0x7f copy N literal palette indices
           0x81..0xff skip N pixels (keep previous frame)
           0x00 CC PP fill CC pixels with PP
           0x80 LL HH extended: count = val & 0x3fff, sub = val >> 14
             sub 0 skip, 1 skip+0x4000, 2 copy, 3 fill PP
  Frames are deltas against the previous frame.  Empty records repeat the
  previous frame.  Verified on all 38 files: 797 records, every non-empty
  record starts with 42 00 01 00 and is consumed exactly.

Usage:
  python3 tools/prepare_m5_media.py              # incremental
  python3 tools/prepare_m5_media.py --force      # rebuild everything
  python3 tools/prepare_m5_media.py --verify     # check only, no conversion

Requires ffmpeg/ffprobe (default {ffmpeg,ffprobe}).
The miniconda ffmpeg has no libtheora, so Theora .ogv playback copies are encoded
with /opt/homebrew/bin/ffmpeg 7.1.1 (override with --ffmpeg-theora).  This is
needed because the installed Godot 4.7.2 exposes VideoStreamTheora only, not
VideoStreamWebM.  No third-party Python packages are used.

  python3 tools/prepare_m5_media.py             # convert (incremental)
  python3 tools/prepare_m5_media.py --force     # rebuild all
  python3 tools/prepare_m5_media.py --verify    # verify only
  python3 tools/verify_m5_media.py              # verify only, standalone
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = PROJECT_ROOT.parent / "dlz" / "ANTI-JAP"
DEFAULT_DEST = PROJECT_ROOT / "godot" / "assets" / "m5"
DEFAULT_DATA = PROJECT_ROOT / "godot" / "data"

DEFAULT_FFMPEG = Path(os.environ.get("M5_FFMPEG", "ffmpeg"))
DEFAULT_FFPROBE = Path(
    os.environ.get("M5_FFPROBE", str(DEFAULT_FFMPEG.with_name("ffprobe")))
)
# The miniconda ffmpeg has libvpx but no libtheora.  This build is used only
# for the .ogv playback copies requested by the parent session.
DEFAULT_THEORA_FFMPEG = Path(
    os.environ.get("M5_FFMPEG_THEORA", "/opt/homebrew/bin/ffmpeg")
)

TARGET_W, TARGET_H = 640, 480
MPEG_CRF = 36
FLC_CRF = 35
THEORA_QUALITY = 4
OGV_FPS = 12
AUDIO_BITRATE = "64k"
ANM_FPS = 12
ANM_CRF = 35
MEDIA_BUDGET = 350 * 1024 * 1024
ANM_RAW_BUDGET = 7 * 1024 * 1024

VARIANTS = {"D01A", "D07A", "D10A", "D14A", "D28A"}
FLC_ORDER = ["KINGSOFT", "KR-1", "TEST01", "TRAIN"]
EXPECTED_MPEG = 33
EXPECTED_FLC = 4
EXPECTED_ANM = 38

VERSION = 1


class ConversionError(RuntimeError):
    pass


# --------------------------------------------------------------------------
# small helpers


def human(n: int | float) -> str:
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024


def parse_ratio(value: str | None) -> float | None:
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


def parse_fps(value: str | None) -> float | None:
    return parse_ratio(value)


def is_fresh(out: Path, src: Path, force: bool) -> bool:
    if force:
        return False
    try:
        st = out.stat()
    except OSError:
        return False
    if st.st_size <= 0:
        return False
    try:
        return st.st_mtime >= src.stat().st_mtime - 1.0
    except OSError:
        return False


def write_json(path: Path, obj) -> bool:
    """Atomically write canonical JSON. Return True if content changed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
    if path.exists():
        try:
            if path.read_text(encoding="utf-8") == text:
                return False
        except OSError:
            pass
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)
    return True


def resolve_tool(path: Path, what: str) -> Path:
    if path.is_file() and os.access(path, os.X_OK):
        return path
    found = shutil.which(str(path)) or shutil.which(path.name)
    if found:
        return Path(found)
    raise SystemExit(f"error: {what} not found at {path}")


def has_encoder(ffmpeg: Path, name: str) -> bool:
    proc = subprocess.run(
        [str(ffmpeg), "-hide_banner", "-encoders"], capture_output=True, text=True
    )
    return proc.returncode == 0 and re.search(rf"\b{re.escape(name)}\b", proc.stdout) is not None


def pick_theora_ffmpeg(explicit: Path) -> Path:
    """The miniconda ffmpeg lacks libtheora; find a build that has it."""
    candidates = [
        explicit,
        DEFAULT_THEORA_FFMPEG,
        Path("/opt/homebrew/bin/ffmpeg"),
        Path(shutil.which("ffmpeg") or ""),
        DEFAULT_FFMPEG,
    ]
    for candidate in candidates:
        if not str(candidate) or not candidate.is_file() or not os.access(candidate, os.X_OK):
            continue
        if has_encoder(candidate, "libtheora"):
            return candidate
    raise SystemExit(
        "error: no ffmpeg with libtheora found; pass --ffmpeg-theora "
        "(checked /opt/homebrew/bin/ffmpeg and the WebM ffmpeg)"
    )


# --------------------------------------------------------------------------
# ffprobe / ffmpeg


def ffprobe_json(ffprobe: Path, path: Path) -> dict:
    cmd = [
        str(ffprobe),
        "-v",
        "error",
        "-show_entries",
        "format=duration,size,format_name",
        "-show_entries",
        "stream=index,codec_type,codec_name,width,height,"
        "sample_aspect_ratio,display_aspect_ratio,avg_frame_rate,"
        "r_frame_rate,channels,sample_rate",
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ConversionError(f"ffprobe failed for {path}: {proc.stderr.strip()[:500]}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise ConversionError(f"bad ffprobe JSON for {path}: {exc}") from exc


def probe_media(ffprobe: Path, path: Path) -> dict:
    raw = ffprobe_json(ffprobe, path)
    fmt = raw.get("format", {})
    streams = raw.get("streams", [])
    v = next((s for s in streams if s.get("codec_type") == "video"), None)
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)
    duration = parse_ratio(fmt.get("duration"))
    size = int(fmt["size"]) if fmt.get("size") not in (None, "N/A") else path.stat().st_size
    info = {
        "duration": round(duration, 3) if duration is not None else 0.0,
        "size_bytes": size,
        "has_audio": a is not None,
        "video_codec": v.get("codec_name") if v else None,
        "audio_codec": a.get("codec_name") if a else None,
    }
    if v:
        info.update(
            width=int(v.get("width") or 0),
            height=int(v.get("height") or 0),
            sar=v.get("sample_aspect_ratio"),
            dar=v.get("display_aspect_ratio"),
        )
    if a:
        info.update(
            channels=int(a.get("channels") or 0),
            sample_rate=int(a.get("sample_rate") or 0),
        )
    fps = None
    if v:
        fps = parse_fps(v.get("avg_frame_rate")) or parse_fps(v.get("r_frame_rate"))
    info["fps"] = round(fps, 3) if fps else None
    return info


def run_ffmpeg(cmd: list[str], what: str, capture_warnings: bool = False) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = (proc.stderr or "").strip().splitlines()[-8:]
        raise ConversionError(f"{what} failed (exit {proc.returncode}): " + " | ".join(tail))
    return proc.stderr if capture_warnings else ""


def ffmpeg_base(ffmpeg: Path) -> list[str]:
    return [str(ffmpeg), "-y", "-hide_banner", "-loglevel", "warning"]


def scale_filter(info: dict) -> str:
    """Fit into 640x480.  4:3 sources fill it; odd aspect ratios keep pillars."""
    w, h = int(info["width"]), int(info["height"])
    dar = parse_ratio(info.get("dar")) or parse_ratio(info.get("sar"))
    if dar is None and h:
        dar = w / h
    if w == 320 and h == 200 or w == 352 and h == 240:
        flags = "neighbor"
    elif dar is not None and abs(dar - 4 / 3) <= 0.02:
        return "scale=640:480:flags=lanczos,setsar=1"
    else:
        flags = "lanczos"
    return (
        "scale=640:480:force_original_aspect_ratio=decrease:"
        f"flags={flags},"
        "pad=640:480:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
    )


def ogv_filter(info: dict) -> str:
    """Theora playback copies are capped at 12 fps to keep the media budget."""
    return f"fps={OGV_FPS}," + scale_filter(info)


def encode_ogv(
    theora_ffmpeg: Path,
    ffprobe: Path,
    src: Path,
    dst: Path,
    src_info: dict,
    force: bool,
    keep_audio: bool,
) -> tuple[dict, bool]:
    if is_fresh(dst, src, force):
        return probe_media(ffprobe, dst), True
    dst.parent.mkdir(parents=True, exist_ok=True)
    part = dst.with_name(dst.name + ".part")
    part.unlink(missing_ok=True)
    cmd = [
        str(theora_ffmpeg),
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(src),
        "-map",
        "0:v:0",
    ]
    if keep_audio:
        cmd += ["-map", "0:a:0?"]
    cmd += [
        "-vf",
        ogv_filter(src_info),
        "-c:v",
        "libtheora",
        "-q:v",
        str(THEORA_QUALITY),
        "-pix_fmt",
        "yuv420p",
    ]
    if keep_audio:
        cmd += ["-c:a", "libvorbis", "-b:a", AUDIO_BITRATE]
    else:
        cmd += ["-an"]
    cmd += ["-f", "ogg", str(part)]
    try:
        run_ffmpeg(cmd, f"Theora {src.name}")
        os.replace(part, dst)
    finally:
        part.unlink(missing_ok=True)
    info = probe_media(ffprobe, dst)
    if info["duration"] <= 0:
        raise ConversionError(f"{dst.name}: zero duration")
    if (info.get("width"), info.get("height")) != (TARGET_W, TARGET_H):
        raise ConversionError(
            f"{dst.name}: expected {TARGET_W}x{TARGET_H}, got "
            f"{info.get('width')}x{info.get('height')}"
        )
    if info.get("video_codec") != "theora":
        raise ConversionError(f"{dst.name}: expected Theora, got {info.get('video_codec')}")
    if keep_audio and not info.get("has_audio"):
        raise ConversionError(f"{dst.name}: source audio was not kept")
    return info, False


# --------------------------------------------------------------------------
# MPEG


def mpeg_id(stem: str) -> str:
    return stem.lower()


def mpeg_story(clip_id: str) -> dict:
    m = re.fullmatch(r"d(\d{2})(a?)", clip_id)
    if not m:
        raise ConversionError(f"unexpected MPEG name: {clip_id}")
    num = int(m.group(1))
    variant = bool(m.group(2))
    return {
        "chapter": num,
        "level_index": num - 1,
        "variant": variant,
        "variant_of": f"d{num:02d}" if variant else None,
    }


def discover_mpegs(src: Path) -> list[tuple[Path, str]]:
    files = sorted(
        {p.resolve(): p for p in (list((src / "MPEG").glob("*.MPG")) + list((src / "MPEG").glob("*.mpg")))}
        .values(),
        key=lambda p: p.name.lower(),
    )
    return [(p, mpeg_id(p.stem)) for p in files]


def convert_mpeg(
    ffmpeg: Path,
    theora_ffmpeg: Path,
    ffprobe: Path,
    src: Path,
    dest: Path,
    force: bool,
    video_id: str,
) -> dict:
    outdir = dest / "video"
    outdir.mkdir(parents=True, exist_ok=True)
    dst = outdir / f"{video_id}.webm"
    ogv_dst = outdir / f"{video_id}.ogv"
    src_info = probe_media(ffprobe, src)
    if not src_info.get("width"):
        raise ConversionError(f"{src.name}: no video stream")

    if is_fresh(dst, src, force):
        out_info = probe_media(ffprobe, dst)
        skipped = True
    else:
        part = dst.with_name(dst.name + ".part")
        part.unlink(missing_ok=True)
        cmd = ffmpeg_base(ffmpeg) + [
            "-i",
            str(src),
            "-map",
            "0:v:0",
            "-map",
            "0:a:0?",
            "-vf",
            scale_filter(src_info),
            "-c:v",
            "libvpx-vp9",
            "-crf",
            str(MPEG_CRF),
            "-b:v",
            "0",
            "-row-mt",
            "1",
            "-cpu-used",
            "4",
            "-deadline",
            "good",
            "-g",
            "240",
            "-c:a",
            "libvorbis",
            "-b:a",
            AUDIO_BITRATE,
            "-f",
            "webm",
            str(part),
        ]
        try:
            run_ffmpeg(cmd, f"MPEG {src.name}")
            os.replace(part, dst)
        finally:
            part.unlink(missing_ok=True)
        out_info = probe_media(ffprobe, dst)
        skipped = False

    if out_info["duration"] <= 0:
        raise ConversionError(f"{dst.name}: zero duration")
    if (out_info.get("width"), out_info.get("height")) != (TARGET_W, TARGET_H):
        raise ConversionError(
            f"{dst.name}: expected {TARGET_W}x{TARGET_H}, got "
            f"{out_info.get('width')}x{out_info.get('height')}"
        )
    if src_info["has_audio"] and not out_info["has_audio"]:
        raise ConversionError(f"{dst.name}: source audio was not kept")

    ogv_info, ogv_skipped = encode_ogv(
        theora_ffmpeg, ffprobe, src, ogv_dst, src_info, force, src_info["has_audio"]
    )
    if ogv_info.get("fps") and ogv_info["fps"] > OGV_FPS + 0.1:
        raise ConversionError(f"{ogv_dst.name}: fps {ogv_info['fps']} > {OGV_FPS}")

    story = mpeg_story(video_id)
    entry = {
        "kind": "mpeg",
        "id": video_id,
        "source": f"MPEG/{src.name}",
        "path": f"res://assets/m5/video/{dst.name}",
        "ogv_path": f"res://assets/m5/video/{ogv_dst.name}",
        "duration": out_info["duration"],
        "size_bytes": out_info["size_bytes"],
        "ogv_duration": ogv_info["duration"],
        "ogv_size_bytes": ogv_info["size_bytes"],
        "source_size_bytes": src.stat().st_size,
        "source_duration": src_info["duration"],
        "width": TARGET_W,
        "height": TARGET_H,
        "aspect": "4:3",
        "has_audio": out_info["has_audio"],
        "video_codec": out_info["video_codec"],
        "audio_codec": out_info["audio_codec"],
        "fps": out_info["fps"],
        "ogv_video_codec": ogv_info.get("video_codec"),
        "ogv_audio_codec": ogv_info.get("audio_codec"),
        "ogv_fps": ogv_info.get("fps"),
        **story,
    }
    return {"entry": entry, "skipped": skipped and ogv_skipped}


# --------------------------------------------------------------------------
# FLC


def discover_flcs(src: Path) -> list[tuple[Path, str]]:
    out = []
    for stem in FLC_ORDER:
        path = src / f"{stem}.FLC"
        if not path.is_file():
            raise ConversionError(f"missing FLC: {path}")
        out.append((path, stem.lower()))
    return out


def flc_filter(ffprobe: Path, src: Path) -> tuple[str, float]:
    raw = ffprobe_json(ffprobe, src)
    stream = next((s for s in raw.get("streams", []) if s.get("codec_type") == "video"), {})
    native = parse_fps(stream.get("avg_frame_rate")) or parse_fps(stream.get("r_frame_rate"))
    # The FLC demuxer reports 200 fps for TEST01 (speed field is 0); cap at 12.
    target = 12.0 if not native or native > 12.0 else native
    target_text = "12" if target >= 12.0 else f"{target:.6f}".rstrip("0").rstrip(".")
    filt = f"fps={target_text},scale=640:480:flags=lanczos,setsar=1"
    return filt, round(target, 3)


def scan_flc(ffmpeg: Path, src: Path) -> tuple[int, list[str]]:
    """Count FLI_COPY chunks the FLC demuxer rejects (KR-1=4, TEST01=15)."""
    cmd = [
        str(ffmpeg),
        "-hide_banner",
        "-loglevel",
        "warning",
        "-i",
        str(src),
        "-map",
        "0:v:0",
        "-f",
        "null",
        "-",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    count = 0
    lines: list[str] = []
    for line in (proc.stderr or "").splitlines():
        if "incorrect size" in line and "skipping chunk" in line:
            count += 1
            # Strip ffmpeg's per-process pointer so the manifest is reproducible.
            clean = re.sub(r"\[flic @ 0x[0-9a-fA-F]+\]", "[flic]", line.strip())
            lines.append(clean)
        else:
            m = re.search(r"Last message repeated (\d+) times?", line)
            if m:
                count += int(m.group(1))
    return count, lines[:8]


def convert_flc(
    ffmpeg: Path,
    theora_ffmpeg: Path,
    ffprobe: Path,
    src: Path,
    dest: Path,
    force: bool,
) -> dict:
    video_id = src.stem.lower()
    dst = dest / "flc" / f"{video_id}.webm"
    ogv_dst = dest / "flc" / f"{video_id}.ogv"
    dst.parent.mkdir(parents=True, exist_ok=True)
    src_info = probe_media(ffprobe, src)
    skipped_chunks, warnings = scan_flc(ffmpeg, src)
    skipped = False
    if is_fresh(dst, src, force):
        out_info = probe_media(ffprobe, dst)
        skipped = True
    else:
        filt, _target_fps = flc_filter(ffprobe, src)
        part = dst.with_name(dst.name + ".part")
        part.unlink(missing_ok=True)
        cmd = ffmpeg_base(ffmpeg) + [
            "-i",
            str(src),
            "-vf",
            filt,
            "-an",
            "-c:v",
            "libvpx-vp9",
            "-crf",
            str(FLC_CRF),
            "-b:v",
            "0",
            "-row-mt",
            "1",
            "-cpu-used",
            "4",
            "-deadline",
            "good",
            "-g",
            "240",
            "-f",
            "webm",
            str(part),
        ]
        try:
            run_ffmpeg(cmd, f"FLC {src.name}")
            os.replace(part, dst)
        finally:
            part.unlink(missing_ok=True)
        out_info = probe_media(ffprobe, dst)
    if out_info["duration"] <= 0:
        raise ConversionError(f"{dst.name}: zero duration")
    if (out_info.get("width"), out_info.get("height")) != (TARGET_W, TARGET_H):
        raise ConversionError(
            f"{dst.name}: expected {TARGET_W}x{TARGET_H}, got "
            f"{out_info.get('width')}x{out_info.get('height')}"
        )

    ogv_info, ogv_skipped = encode_ogv(
        theora_ffmpeg, ffprobe, src, ogv_dst, src_info, force, False
    )
    if ogv_info.get("fps") and ogv_info["fps"] > OGV_FPS + 0.1:
        raise ConversionError(f"{ogv_dst.name}: fps {ogv_info['fps']} > {OGV_FPS}")

    entry = {
        "kind": "flc",
        "id": video_id,
        "source": src.name,
        "path": f"res://assets/m5/flc/{dst.name}",
        "ogv_path": f"res://assets/m5/flc/{ogv_dst.name}",
        "duration": out_info["duration"],
        "size_bytes": out_info["size_bytes"],
        "ogv_duration": ogv_info["duration"],
        "ogv_size_bytes": ogv_info["size_bytes"],
        "source_size_bytes": src.stat().st_size,
        "width": TARGET_W,
        "height": TARGET_H,
        "aspect": "4:3",
        "has_audio": False,
        "video_codec": out_info["video_codec"],
        "audio_codec": None,
        "fps": out_info["fps"],
        "ogv_video_codec": ogv_info.get("video_codec"),
        "ogv_audio_codec": ogv_info.get("audio_codec"),
        "ogv_fps": ogv_info.get("fps"),
        "chapter": None,
        "level_index": None,
        "variant": False,
        "variant_of": None,
        "skipped_chunks": skipped_chunks,
        "decode_warnings": warnings,
    }
    return {"entry": entry, "skipped": skipped and ogv_skipped}


# --------------------------------------------------------------------------
# ANM


def u16(buf: bytes, off: int) -> int:
    return struct.unpack_from("<H", buf, off)[0]


def u32(buf: bytes, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


def parse_anm(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 0x500:
        raise ConversionError(f"{path.name}: too small for LPF/ANIM header")
    if data[0:4] != b"LPF ":
        raise ConversionError(f"{path.name}: bad magic {data[0:4]!r}")
    if data[0x10:0x14] != b"ANIM":
        raise ConversionError(f"{path.name}: missing ANIM at 0x10")
    pages_num = u16(data, 0x06)
    records_num = u32(data, 0x08)
    page_table_off = u16(data, 0x0E)
    width = u16(data, 0x14)
    height = u16(data, 0x16)
    frames_num = u32(data, 0x40)
    rate_byte = data[0x19]
    info = u16(data, 0x44)
    if width != 320 or height != 200:
        raise ConversionError(f"{path.name}: unexpected frame size {width}x{height}")
    if page_table_off != 0x500:
        raise ConversionError(f"{path.name}: unexpected page table offset 0x{page_table_off:x}")
    page_data_off = page_table_off + 0x600  # 256 reserved 6-byte page-table slots
    if page_data_off >= len(data):
        raise ConversionError(f"{path.name}: page data offset outside file")

    pages = []
    records: dict[int, bytes] = {}
    duplicate_indices: list[int] = []
    for pg in range(pages_num):
        off = page_data_off + pg * 0x10000
        if off + 8 > len(data):
            raise ConversionError(f"{path.name}: page {pg} header outside file")
        base_rec, nb_recs, page_size, pad = struct.unpack_from("<HHHH", data, off)
        if pad != 0:
            raise ConversionError(f"{path.name}: page {pg} pad != 0 ({pad})")
        if nb_recs:
            table_end = off + 8 + nb_recs * 2
            if table_end > len(data):
                raise ConversionError(f"{path.name}: page {pg} size table outside file")
            sizes = struct.unpack_from(f"<{nb_recs}H", data, off + 8)
            if sum(sizes) != page_size:
                raise ConversionError(
                    f"{path.name}: page {pg} record bytes {sum(sizes)} != header {page_size}"
                )
            pos = table_end
            for i, size in enumerate(sizes):
                if pos + size > len(data):
                    raise ConversionError(f"{path.name}: page {pg} record {i} outside file")
                idx = base_rec + i
                rec = data[pos : pos + size]
                if idx in records:
                    duplicate_indices.append(idx)
                else:
                    records[idx] = rec
                pos += size
            pages.append(
                {
                    "page": pg,
                    "base_record": base_rec,
                    "records": nb_recs,
                    "record_bytes": page_size,
                    "single_record": False,
                }
            )
        else:
            if off + 8 + page_size > len(data):
                raise ConversionError(f"{path.name}: page {pg} single record outside file")
            idx = base_rec
            rec = data[off + 8 : off + 8 + page_size]
            if idx in records:
                duplicate_indices.append(idx)
            else:
                records[idx] = rec
            pages.append(
                {
                    "page": pg,
                    "base_record": base_rec,
                    "records": 0,
                    "record_bytes": page_size,
                    "single_record": True,
                }
            )

    missing = [i for i in range(max(records) + 1) if i not in records]
    if missing:
        raise ConversionError(f"{path.name}: missing record indices {missing[:8]}")
    if len(records) != frames_num or len(records) != records_num:
        raise ConversionError(
            f"{path.name}: unique records={len(records)}, header frames={frames_num}, "
            f"header records={records_num}"
        )

    for idx, rec in records.items():
        if rec and rec[:4] != b"\x42\x00\x01\x00":
            raise ConversionError(f"{path.name}: record {idx} has bad header {rec[:4]!r}")

    palette = data[0x100:0x500]
    return {
        "data": data,
        "path": path,
        "width": width,
        "height": height,
        "pages_num": pages_num,
        "records_num": records_num,
        "frames": frames_num,
        "rate_byte": rate_byte,
        "info": info,
        "page_table_offset": page_table_off,
        "page_data_offset": page_data_off,
        "palette": palette,
        "pages": pages,
        "records": records,
        "sorted_indices": sorted(records),
        "duplicate_indices": duplicate_indices,
        "zero_length_records": [i for i, r in records.items() if len(r) == 0],
        "record_bytes_total": sum(len(r) for r in records.values()),
        "header_hex": " ".join(f"{b:02x}" for b in data[:0x20]),
    }


def decode_anm_record(rec: bytes, prev: bytearray) -> bytearray:
    """Apply one delta RLE record on top of prev. Record header already checked."""
    out = bytearray(prev)
    pos = 4
    dst = 0
    n = len(rec)
    frame_size = len(out)
    while pos < n:
        tb = rec[pos]
        pos += 1
        count = tb & 0x7F
        op = tb >> 7
        if count:
            if op == 0:  # copy literals
                take = min(count, n - pos)
                if dst + take > frame_size:
                    raise ConversionError(f"RLE overruns frame by {dst + take - frame_size}")
                out[dst : dst + take] = rec[pos : pos + take]
                pos += take
                dst += take
            else:  # skip, keep previous frame pixels
                dst += count
                if dst > frame_size:
                    raise ConversionError(f"RLE skip overruns frame by {dst - frame_size}")
        elif op == 0:  # 0x00 CC PP: fill
            if pos + 1 >= n:
                raise ConversionError("truncated fill command")
            count = rec[pos]
            pixel = rec[pos + 1]
            pos += 2
            if dst + count > frame_size:
                raise ConversionError(f"RLE overruns frame by {dst + count - frame_size}")
            out[dst : dst + count] = bytes([pixel]) * count
            dst += count
        else:  # 0x80 LL HH
            if pos + 1 >= n:
                raise ConversionError("truncated extended command")
            val = struct.unpack_from("<H", rec, pos)[0]
            pos += 2
            count = val & 0x3FFF
            sub = val >> 14
            if count == 0:
                if sub in (0, 2):  # stop
                    break
                continue
            pixel = None
            if sub == 3:
                if pos >= n:
                    raise ConversionError("truncated extended fill pixel")
                pixel = rec[pos]
                pos += 1
            if sub == 1:
                count += 0x4000
            if sub in (0, 1):  # skip
                dst += count
                if dst > frame_size:
                    raise ConversionError(f"RLE skip overruns frame by {dst - frame_size}")
            elif sub == 2:  # copy
                take = min(count, n - pos)
                if dst + take > frame_size:
                    raise ConversionError(f"RLE overruns frame by {dst + take - frame_size}")
                out[dst : dst + take] = rec[pos : pos + take]
                pos += take
                dst += take
            else:  # fill
                if dst + count > frame_size:
                    raise ConversionError(f"RLE overruns frame by {dst + count - frame_size}")
                out[dst : dst + count] = bytes([pixel]) * count
                dst += count
    if pos != n:
        raise ConversionError(f"RLE trailing bytes: consumed {pos}/{n}")
    return out


def anm_frames(parsed: dict):
    """Yield 320x200 palette-index frames in record order (delta applied)."""
    prev = bytearray(parsed["width"] * parsed["height"])
    for idx in parsed["sorted_indices"]:
        rec = parsed["records"][idx]
        if rec:
            prev = decode_anm_record(rec, prev)
        # else: empty record repeats the previous frame
        yield idx, bytes(prev)


def battle_anm_signature(parsed: dict) -> dict:
    """Battle surfaces retain KUANG04; ANM's own palette is preview-only.

    404AA7/4264F6 exclude the final loop-back record. Keep preview and battle
    frame counts separate, and invalidate old sheets even on incremental runs.
    """
    source = Path(parsed["path"])
    palette = (source.parent / "KUANG04.IMG").read_bytes()[-768:]
    return {"policy": "kuang04-records-minus-one-v1",
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "palette_sha256": hashlib.sha256(palette).hexdigest(),
            "decoded_records": len(parsed["sorted_indices"]), "battle_frame_ms": 50,
            "battle_frames": (int(parsed["records_num"]) & 0xffff) - 1}


def encode_anm_alpha_sheet(parsed: dict, dst: Path) -> int:
    """Battle-only RGBA sheet: KUANG04, index0 transparent, native N-1 frames."""
    w, h = parsed["width"], parsed["height"]
    signature = battle_anm_signature(parsed)
    palette = bytes(v * 4 for v in (Path(parsed["path"]).parent / "KUANG04.IMG").read_bytes()[-768:])
    n = signature["battle_frames"]
    if n < 1 or n > signature["decoded_records"]:
        raise ConversionError("ANM native record bound outside decoded records")
    frames = []
    for _, frame in anm_frames(parsed):
        indexed = Image.frombytes("P", (w, h), frame)
        indexed.putpalette(palette)
        rgba = indexed.convert("RGBA")
        rgba.putalpha(Image.frombytes("L", (w, h), frame).point([0] + [255] * 255))
        frames.append(rgba)
        if len(frames) == n:
            break
    if not frames:
        return 0
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        sheet.paste(im, (i * w, 0))
    dst.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dst)
    dst.with_suffix(".json").write_text(json.dumps(signature, indent=2) + "\n")
    return len(frames)


def encode_anm(ffmpeg: Path, ffprobe: Path, parsed: dict, dst: Path) -> dict:
    dst.parent.mkdir(parents=True, exist_ok=True)
    part = dst.with_name(dst.name + ".part")
    part.unlink(missing_ok=True)
    palette = parsed["palette"]
    rgb = []
    for i in range(256):
        b, g, r, _ = palette[i * 4 : i * 4 + 4]
        rgb.append(bytes((r, g, b)))
    cmd = [
        str(ffmpeg),
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{parsed['width']}x{parsed['height']}",
        "-r",
        str(ANM_FPS),
        "-i",
        "-",
        "-an",
        "-c:v",
        "libvpx-vp9",
        "-crf",
        str(ANM_CRF),
        "-b:v",
        "0",
        "-row-mt",
        "1",
        "-cpu-used",
        "4",
        "-deadline",
        "good",
        "-g",
        "240",
        "-f",
        "webm",
        str(part),
    ]
    errlog = tempfile.TemporaryFile(mode="w+")
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=errlog)
    count = 0
    try:
        assert proc.stdin is not None
        for _, frame in anm_frames(parsed):
            proc.stdin.write(b"".join(rgb[v] for v in frame))
            count += 1
        proc.stdin.close()
        rc = proc.wait()
        if rc != 0:
            errlog.seek(0)
            tail = errlog.read().strip().splitlines()[-8:]
            raise ConversionError(
                f"ANM {parsed['path'].name}: encoder exit {rc}: " + " | ".join(tail)
            )
        if count != parsed["frames"]:
            raise ConversionError(
                f"ANM {parsed['path'].name}: encoded {count} frames, header says {parsed['frames']}"
            )
        os.replace(part, dst)
    except (BrokenPipeError, ConversionError) as exc:
        proc.kill()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        raise ConversionError(str(exc))
    finally:
        errlog.close()
        part.unlink(missing_ok=True)
    return {"frames": count}


def convert_anm(
    ffmpeg: Path, ffprobe: Path, src: Path, dest: Path, force: bool
) -> dict:
    parsed = parse_anm(src)
    video_id = src.stem.lower()
    dst = dest / "anm" / f"{video_id}.webm"
    header = {
        "pages": parsed["pages_num"],
        "records": parsed["records_num"],
        "frames": parsed["frames"],
        "width": parsed["width"],
        "height": parsed["height"],
        "rate_byte": parsed["rate_byte"],
        "info": parsed["info"],
        "page_table_offset": parsed["page_table_offset"],
        "page_data_offset": parsed["page_data_offset"],
        "record_bytes": parsed["record_bytes_total"],
        "header_hex": parsed["header_hex"],
    }
    decode_info = {
        "width": parsed["width"],
        "height": parsed["height"],
        "frames": parsed["frames"],
        "fps": ANM_FPS,
        "duration": round(parsed["frames"] / ANM_FPS, 3),
        "zero_length_records": len(parsed["zero_length_records"]),
        "extra_single_record_pages": len(parsed["duplicate_indices"]),
        "decoded": False,
    }
    if not force and is_fresh(dst, src, False):
        out_info = probe_media(ffprobe, dst)
        decode_info.update(
            decoded=True,
            webm_path=f"res://assets/m5/anm/{dst.name}",
            size_bytes=out_info["size_bytes"],
            duration=out_info["duration"] or decode_info["duration"],
        )
        skipped = True
    else:
        try:
            encode_anm(ffmpeg, ffprobe, parsed, dst)
            out_info = probe_media(ffprobe, dst)
        except ConversionError as exc:
            decode_info["decoded"] = False
            decode_info["reason"] = str(exc)
            return {
                "id": video_id,
                "source": src.name,
                "source_size_bytes": src.stat().st_size,
                "header": header,
                "decoded": False,
                "decode_error": str(exc),
                "decode": decode_info,
            }
        if out_info["duration"] <= 0:
            decode_info["decoded"] = False
            decode_info["reason"] = "decoded WebM has zero duration"
            return {
                "id": video_id,
                "source": src.name,
                "source_size_bytes": src.stat().st_size,
                "header": header,
                "decoded": False,
                "decode_error": decode_info["reason"],
                "decode": decode_info,
            }
        if (out_info.get("width"), out_info.get("height")) != (
            parsed["width"],
            parsed["height"],
        ):
            decode_info["decoded"] = False
            decode_info["reason"] = (
                f"decoded WebM is {out_info.get('width')}x{out_info.get('height')}, "
                f"expected {parsed['width']}x{parsed['height']}"
            )
            return {
                "id": video_id,
                "source": src.name,
                "source_size_bytes": src.stat().st_size,
                "header": header,
                "decoded": False,
                "decode_error": decode_info["reason"],
                "decode": decode_info,
            }
        decode_info.update(
            decoded=True,
            webm_path=f"res://assets/m5/anm/{dst.name}",
            size_bytes=out_info["size_bytes"],
            duration=out_info["duration"],
        )
        skipped = False
    if video_id.startswith("mine") or video_id.startswith("ffpact"):
        sheet = dest / "anm" / f"{video_id}_sheet.png"
        signature = battle_anm_signature(parsed)
        cached = json.loads(sheet.with_suffix(".json").read_text()) if sheet.with_suffix(".json").exists() else {}
        if force or not sheet.exists() or cached != signature:
            try:
                encode_anm_alpha_sheet(parsed, sheet)
            except Exception as exc:
                decode_info["sheet_error"] = str(exc)
        decode_info.update(sheet_path=f"res://assets/m5/anm/{sheet.name}",
                           sheet_frames=signature["battle_frames"],
                           battle_sheet=signature)
    return {
        "id": video_id,
        "source": src.name,
        "source_size_bytes": src.stat().st_size,
        "raw_path": f"res://assets/m5/anm/{video_id}.anm",
        "header": header,
        "decoded": True,
        "decode": decode_info,
        "skipped": skipped,
    }


# --------------------------------------------------------------------------
# main


def copy_anm_raw(src_files: list[Path], dest: Path, force: bool) -> tuple[bool, str, int, int]:
    total = sum(p.stat().st_size for p in src_files)
    if total >= ANM_RAW_BUDGET:
        return (
            False,
            f"raw ANM total {total} bytes >= {ANM_RAW_BUDGET} byte budget; not copied",
            total,
            0,
        )
    dest.mkdir(parents=True, exist_ok=True)
    copied = 0
    for p in src_files:
        dst = dest / f"{p.stem.lower()}.anm"
        if not force and dst.exists() and dst.stat().st_size == p.stat().st_size:
            continue
        shutil.copy2(p, dst)
        copied += 1
    return True, "", total, copied


def run(args) -> int:
    started = time.time()
    ffmpeg = resolve_tool(Path(args.ffmpeg), "ffmpeg")
    ffprobe = resolve_tool(Path(args.ffprobe), "ffprobe")
    theora_ffmpeg = pick_theora_ffmpeg(Path(args.ffmpeg_theora))
    src = Path(args.src).resolve()
    dest = Path(args.dest).resolve()
    data_dir = Path(args.data).resolve()
    if not src.is_dir():
        raise SystemExit(f"error: source directory not found: {src}")
    dest.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)

    only = set(args.only.split(",")) if args.only != "all" else {"mpeg", "flc", "anm"}
    unknown = only - {"mpeg", "flc", "anm"}
    if unknown:
        raise SystemExit(f"error: unknown --only values: {sorted(unknown)}")

    failures: list[str] = []
    # built, up-to-date, WebM bytes, OGV bytes
    stats = {
        "mpeg": [0, 0, 0, 0],
        "flc": [0, 0, 0, 0],
        "anm": [0, 0, 0, 0],
    }
    clips: list[dict] = []
    warnings: list[str] = []

    if "mpeg" in only:
        mpegs = discover_mpegs(src)
        if len(mpegs) != EXPECTED_MPEG:
            raise SystemExit(f"error: expected {EXPECTED_MPEG} MPEGs, found {len(mpegs)}")
        print(f"MPEG: {len(mpegs)} source files -> {dest / 'video'} (webm + ogv)")
        for i, (path, vid) in enumerate(mpegs, 1):
            try:
                res = convert_mpeg(
                    ffmpeg, theora_ffmpeg, ffprobe, path, dest, args.force, vid
                )
                clips.append(res["entry"])
                if res["skipped"]:
                    stats["mpeg"][1] += 1
                else:
                    stats["mpeg"][0] += 1
                stats["mpeg"][2] += res["entry"]["size_bytes"]
                stats["mpeg"][3] += res["entry"]["ogv_size_bytes"]
                print(
                    f"  [{i:02d}/{len(mpegs)}] {vid}  "
                    f"{res['entry']['duration']:.1f}s  "
                    f"webm {human(res['entry']['size_bytes'])}  "
                    f"ogv {human(res['entry']['ogv_size_bytes'])}"
                    + ("  (up to date)" if res["skipped"] else "")
                )
            except ConversionError as exc:
                failures.append(f"MPEG {path.name}: {exc}")
                print(f"  [{i:02d}/{len(mpegs)}] {path.name}: FAILED {exc}")

    if "flc" in only:
        flcs = discover_flcs(src)
        print(f"FLC: {len(flcs)} source files -> {dest / 'flc'}")
        for i, (path, vid) in enumerate(flcs, 1):
            try:
                res = convert_flc(
                    ffmpeg, theora_ffmpeg, ffprobe, path, dest, args.force
                )
                clips.append(res["entry"])
                if res["skipped"]:
                    stats["flc"][1] += 1
                else:
                    stats["flc"][0] += 1
                stats["flc"][2] += res["entry"]["size_bytes"]
                stats["flc"][3] += res["entry"]["ogv_size_bytes"]
                if res["entry"]["decode_warnings"]:
                    warnings.extend(
                        f"FLC {path.name}: {w}" for w in res["entry"]["decode_warnings"]
                    )
                if res["entry"]["skipped_chunks"]:
                    warnings.append(
                        f"FLC {path.name}: {res['entry']['skipped_chunks']} corrupt "
                        "FLI_COPY chunks skipped by the demuxer"
                    )
                print(
                    f"  [{i:02d}/{len(flcs)}] {vid}  "
                    f"{res['entry']['duration']:.2f}s  "
                    f"webm {human(res['entry']['size_bytes'])}  "
                    f"ogv {human(res['entry']['ogv_size_bytes'])}"
                    + ("  (up to date)" if res["skipped"] else "")
                )
            except ConversionError as exc:
                failures.append(f"FLC {path.name}: {exc}")
                print(f"  [{i:02d}/{len(flcs)}] {path.name}: FAILED {exc}")

    anm_files = sorted(src.glob("*.ANM"), key=lambda p: p.name.lower())
    anm_manifest = None
    if "anm" in only:
        if len(anm_files) != EXPECTED_ANM:
            print(f"warning: expected {EXPECTED_ANM} ANMs, found {len(anm_files)}")
        print(f"ANM: {len(anm_files)} source files -> {dest / 'anm'}")
        raw_ok, raw_reason, raw_total, _raw_copied = copy_anm_raw(
            anm_files, dest / "anm", args.force
        )
        if not raw_ok:
            warnings.append(raw_reason)
        anm_entries = []
        anm_frames_total = 0
        anm_decoded = 0
        for i, path in enumerate(anm_files, 1):
            try:
                entry = convert_anm(ffmpeg, ffprobe, path, dest, args.force)
            except ConversionError as exc:
                # Header parse itself failed: still record the facts we can.
                entry = {
                    "id": path.stem.lower(),
                    "source": path.name,
                    "source_size_bytes": path.stat().st_size,
                    "decoded": False,
                    "decode_error": str(exc),
                }
                failures.append(f"ANM {path.name}: {exc}")
            anm_entries.append(entry)
            if entry.get("decoded"):
                anm_decoded += 1
                anm_frames_total += int(entry["header"]["frames"])
                stats["anm"][2] += int(entry["decode"].get("size_bytes", 0))
                if entry.get("skipped"):
                    stats["anm"][1] += 1
                else:
                    stats["anm"][0] += 1
            if entry.get("decoded"):
                dec = entry["decode"]
                print(
                    f"  [{i:02d}/{len(anm_files)}] {entry['id']}.webm  "
                    f"{entry['header']['frames']}f @ {ANM_FPS}fps  "
                    f"{human(dec.get('size_bytes', 0))}"
                    + ("  (up to date)" if entry.get("skipped") else "")
                )
            else:
                print(
                    f"  [{i:02d}/{len(anm_files)}] {entry['id']}: "
                    f"decoded=false ({entry.get('decode_error', '?')})"
                )

        sample = next(
            (e for e in anm_entries if e.get("decoded") and e["source"].upper() == "FFPACT00.ANM"),
            anm_entries[0] if anm_entries else None,
        )
        anm_manifest = {
            "schema": VERSION,
            "generator": "tools/prepare_m5_media.py",
            "format": {
                "name": "LPF/ANIM",
                "decoded": anm_decoded == len(anm_files),
                "frame_size": [320, 200],
                "frame_encoding": "8-bit palette indices, delta RLE",
                "fps_assumed": ANM_FPS,
                "fps_note": "header rate byte is 0 in all files; 12 fps chosen for preview playback",
                "evidence": {
                    "sample": sample["source"] if sample else None,
                    "header_hex": sample.get("header", {}).get("header_hex") if sample else None,
                    "magic": {"offset": 0, "hex": "4c 50 46 20", "ascii": "LPF "},
                    "anim_magic": {"offset": 16, "hex": "41 4e 49 4d", "ascii": "ANIM"},
                    "width_height": {"offset": 20, "width": 320, "height": 200},
                    "pages_used": {"offset": 6, "type": "uint16"},
                    "records": {"offset": 8, "type": "uint32"},
                    "page_table_offset": {"offset": 14, "type": "uint16", "value": 1280},
                    "frames": {"offset": 64, "type": "uint32"},
                    "palette": {
                        "offset": 256,
                        "entries": 256,
                        "entry_bytes": 4,
                        "order": "BGR0",
                        "first_entry_hex": "7b 8f 8f 00",
                    },
                    "page_data_offset": 2816,
                    "page_stride": 65536,
                    "page_header": "uint16 base_record, uint16 nb_records, uint16 record_bytes, uint16 pad",
                    "record_size_table": "uint16[nb_records] immediately after page header",
                    "record_prefix_hex": "42 00 01 00",
                    "page0_sample": {
                        "offset": "0xb00",
                        "bytes_hex": "00 00 09 00 d8 e5 00 00 c8 01 f8 03 80 07",
                        "base_record": 0,
                        "records": 9,
                        "record_bytes": 58840,
                    },
                    "all_files": {
                        "count": len(anm_entries),
                        "source_bytes": sum(e["source_size_bytes"] for e in anm_entries),
                        "frames": anm_frames_total,
                        "zero_length_records": sum(
                            int(e.get("decode", {}).get("zero_length_records", 0))
                            for e in anm_entries
                            if e.get("decoded")
                        ),
                    },
                },
                "rle_ops": [
                    {"op": "0x01-0x7f", "meaning": "copy N literals"},
                    {"op": "0x81-0xff", "meaning": "skip N (keep previous frame)"},
                    {"op": "0x00 CC PP", "meaning": "fill CC pixels with PP"},
                    {
                        "op": "0x80 LL HH",
                        "meaning": "extended: count=val&0x3fff, sub=val>>14; "
                        "0 skip, 1 skip+0x4000, 2 copy, 3 fill",
                    },
                ],
                "notes": [
                    "Frames are deltas against the previous frame; empty records repeat it.",
                    "Every non-empty record starts with 42 00 01 00 and consumes exactly its size.",
                    "FFPACT00 has one extra single-record page (base record 10) duplicating an "
                    "existing index; it is ignored so the decoded frame count follows frames=31.",
                    "Decoded WebM previews keep the palette's grey index-0 background; raw .anm "
                    "copies are retained for engine-accurate (alpha) playback.",
                ],
            },
            "raw": {
                "copied": raw_ok,
                "reason": raw_reason or None,
                "total_bytes": raw_total,
                "path": "res://assets/m5/anm/",
                "budget_bytes": ANM_RAW_BUDGET,
            },
            "summary": {
                "total": len(anm_entries),
                "decoded": anm_decoded,
                "failed": len(anm_entries) - anm_decoded,
                "frames_decoded": anm_frames_total,
                "fps": ANM_FPS,
            },
            "files": [
                {k: v for k, v in entry.items() if k != "skipped"}
                for entry in anm_entries
            ],
        }
        try:
            write_json(data_dir / "m5_anm.json", anm_manifest)
        except OSError as exc:
            failures.append(f"m5_anm.json: {exc}")

    # If only ANM was requested, still write the media manifest from existing
    # MPEG/FLC entries? No: keep manifests independent and avoid partial JSON.
    if "mpeg" in only or "flc" in only:
        # A partial --only run must not drop manifest entries for the other kind.
        missing_kinds = {"mpeg", "flc"} - only
        if missing_kinds:
            existing_path = data_dir / "m5_media.json"
            if existing_path.is_file():
                try:
                    existing = json.loads(existing_path.read_text(encoding="utf-8"))
                    known = {c.get("source") for c in clips}
                    for c in existing.get("clips", []):
                        if c.get("kind") in missing_kinds and c.get("source") not in known:
                            clips.append(c)
                except (OSError, json.JSONDecodeError):
                    pass
        clips.sort(key=lambda c: (c["kind"] != "mpeg", c["id"]))
        by_source = {c["source"]: c["path"] for c in sorted(clips, key=lambda x: x["source"])}
        by_source_ogv = {
            c["source"]: c["ogv_path"]
            for c in sorted(clips, key=lambda x: x["source"])
            if c.get("ogv_path")
        }
        media_manifest = {
            "schema": VERSION,
            "generator": "tools/prepare_m5_media.py",
            "source_root": "../dlz/ANTI-JAP",
            "viewport": {"width": TARGET_W, "height": TARGET_H, "aspect_ratio": "4:3"},
            "godot_playback": "ogv",
            "godot_note": "this Godot 4.7.2 build exposes VideoStreamTheora only; "
            "webm files are the requested deliverable and ogv files are the playback copies",
            "encoding": {
                "webm": {
                    "video": "vp9",
                    "crf_mpeg": MPEG_CRF,
                    "crf_flc": FLC_CRF,
                    "audio": "vorbis",
                    "audio_bitrate": AUDIO_BITRATE,
                },
                "ogv": {
                    "video": "theora",
                    "quality": THEORA_QUALITY,
                    "fps_max": OGV_FPS,
                    "audio": "vorbis",
                    "audio_bitrate": AUDIO_BITRATE,
                    "encoder": "libtheora (Homebrew ffmpeg 7.1.1)",
                },
                "scale_note": "MPEG 352x288 (SAR 178:163, DAR ~4:3) -> 640x480 lanczos; "
                "no letterboxing",
            },
            "counts": {
                "mpeg": sum(1 for c in clips if c["kind"] == "mpeg"),
                "flc": sum(1 for c in clips if c["kind"] == "flc"),
                "total": len(clips),
            },
            "by_source": by_source,
            "by_source_ogv": by_source_ogv,
            "clips": clips,
        }
        try:
            write_json(data_dir / "m5_media.json", media_manifest)
        except OSError as exc:
            failures.append(f"m5_media.json: {exc}")

    media_bytes = sum(p.stat().st_size for p in dest.rglob("*") if p.is_file())
    elapsed = time.time() - started
    print()
    print("M5 summary")
    print(
        f"  MPEG : {stats['mpeg'][0]} built, {stats['mpeg'][1]} up-to-date, "
        f"webm {human(stats['mpeg'][2])} + ogv {human(stats['mpeg'][3])}"
    )
    print(
        f"  FLC  : {stats['flc'][0]} built, {stats['flc'][1]} up-to-date, "
        f"webm {human(stats['flc'][2])} + ogv {human(stats['flc'][3])}"
    )
    if "anm" in only:
        assert anm_manifest is not None
        print(
            f"  ANM  : {anm_manifest['summary']['decoded']}/{anm_manifest['summary']['total']} "
            f"decoded, {anm_manifest['summary']['frames_decoded']} frames, "
            f"{human(stats['anm'][2])} previews + {human(raw_total)} raw"
        )
    print(f"  total generated: {human(media_bytes)}")
    if media_bytes > MEDIA_BUDGET:
        warnings.append(
            f"generated media {human(media_bytes)} exceeds the 350 MiB budget"
        )
    print(f"  manifests: {data_dir / 'm5_media.json'}, {data_dir / 'm5_anm.json'}")
    print(f"  elapsed: {elapsed:.1f}s")
    if warnings:
        print("  warnings:")
        for w in warnings:
            print(f"    - {w}")
    if failures:
        print("  failures:")
        for f in failures:
            print(f"    - {f}")
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert original dlz MPEG/FLC/ANM media for the Godot M5 build.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--src", default=str(DEFAULT_SRC), help="original ANTI-JAP directory")
    parser.add_argument("--dest", default=str(DEFAULT_DEST), help="generated media directory")
    parser.add_argument("--data", default=str(DEFAULT_DATA), help="manifest output directory")
    parser.add_argument("--force", action="store_true", help="rebuild existing outputs")
    parser.add_argument(
        "--only",
        default="all",
        help="comma-separated subset of mpeg,flc,anm (default: all)",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="only verify existing outputs (delegates to verify_m5_media.py)",
    )
    parser.add_argument("--ffmpeg", default=str(DEFAULT_FFMPEG), help="ffmpeg executable (WebM)")
    parser.add_argument(
        "--ffmpeg-theora",
        default=str(DEFAULT_THEORA_FFMPEG),
        help="ffmpeg executable with libtheora (for .ogv)",
    )
    parser.add_argument("--ffprobe", default=str(DEFAULT_FFPROBE), help="ffprobe executable")
    args = parser.parse_args(argv)

    if args.verify:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from verify_m5_media import run_verification  # local sibling module

        return run_verification(
            src=Path(args.src).resolve(),
            dest=Path(args.dest).resolve(),
            data_dir=Path(args.data).resolve(),
            ffprobe=resolve_tool(Path(args.ffprobe), "ffprobe"),
        )
    try:
        return run(args)
    except ConversionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
