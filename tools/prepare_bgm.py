"""从原版 CD 镜像提取 BGM（CD-DA）→ godot/assets/audio/bgm_cd.ogg。

原版用 MCI 播 CD 音轨；镜像 `ISO/抗日地雷战音效光盘.nrg` 是 ISO 数据区 +
连续 CD-DA。这里读取 NRG 的 ISO VolumeSpaceSize，找到数据区结束，把后续
2352 B 扇区的 CD-DA 作为 44.1 kHz/16 bit/立体声 Big Endian PCM 交给 ffmpeg。

产物约 20-30 MB，`godot/assets/` 不入库；首次运行约 20 秒。
"""
from __future__ import annotations

import argparse
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NRG = ROOT.parent / "dlz" / "ANTI-JAP" / "ISO" / "抗日地雷战音效光盘.nrg"
OUT = ROOT / "godot" / "assets" / "audio" / "bgm_cd.ogg"
TITLE = ROOT / "godot" / "assets" / "audio" / "bgm_title.ogg"


def iso_data_end(path: Path) -> int:
    with path.open("rb") as f:
        f.seek(0x4B000 + 16 * 2048)
        pvd = f.read(96)
    if pvd[0:1] != b"\x01" or pvd[1:6] != b"CD001":
        raise RuntimeError("不是 ISO9660 PVD")
    # VolumeSpaceSize: both-endian 32-bit at PVD+80
    le = struct.unpack_from("<I", pvd, 80)[0]
    return 0x4B000 + le * 2048


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--seconds", type=float, default=0.0,
                    help="只取前 N 秒（调试用）")
    args = ap.parse_args()
    if not NRG.exists():
        print("missing", NRG)
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists() and not args.force:
        print("keep", OUT, OUT.stat().st_size)
        return
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    if not Path(ffmpeg).exists():
        print("missing ffmpeg")
        sys.exit(1)
    start = iso_data_end(NRG)
    end = NRG.stat().st_size - 60
    # DAO footer 的音频区到 footer 前；去掉可能的 150 扇区 lead-out 由 ffmpeg 容错。
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
           "-f", "s16be", "-ar", "44100", "-ac", "2", "-i", "pipe:0",
           "-c:a", "libvorbis", "-q:a", "3", str(OUT)]
    if args.seconds > 0:
        cmd = cmd[:-1] + ["-t", str(args.seconds), str(OUT)]
    print("audio", start, "..", end, "bytes", end - start)
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with NRG.open("rb") as f:
        f.seek(start)
        left = end - start
        while left > 0:
            chunk = f.read(min(4 * 1024 * 1024, left))
            if not chunk:
                break
            try:
                p.stdin.write(chunk)
            except BrokenPipeError:
                break
            left -= len(chunk)
    p.stdin.close()
    rc = p.wait()
    if rc != 0:
        print("ffmpeg failed", rc)
        sys.exit(rc)
    print("bgm", OUT, OUT.stat().st_size)
    # 原版 CD 是多轨；第一段 5.8–167.5s 作为标题/城镇循环，避免整张 32 分钟循环。
    if not TITLE.exists() or args.force:
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                        "-ss", "5.8", "-to", "167.5", "-i", str(OUT),
                        "-c:a", "libvorbis", "-q:a", "3", str(TITLE)], check=False)
        print("title", TITLE, TITLE.stat().st_size if TITLE.exists() else 0)


if __name__ == "__main__":
    main()
