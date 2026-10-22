"""WAVE.DAT 音效解码器。

结构（本机验证）：

    0x0000  8,192 B   Index[1024] × (u32 offset, u32 length)
    0x2000   ...      PCM 数据

* offset 相对 PCM 区（0x2000）起点。
* 1024 项里只有 152 项 length > 0；其余是占位（offset 保持在上一个结束处）。
* 所有项首尾相接，`sum(length) == 文件长度 - 8192`。
* PCM 格式：22050 Hz、单声道、16 bit signed little-endian
  （来自 dlz_research 的模板结论；导出 WAV 后可由播放器复核）。

索引号即游戏里的音效 ID：GAME.DAT 的 `audio_gongji` / `audio_yidong`
以及 TOWN.DAT 的 803/808/812 等都直接落在这张表里。
"""

from __future__ import annotations

import struct
import wave
from dataclasses import dataclass
from pathlib import Path

INDEX_SIZE = 8192
ENTRY_COUNT = 1024
ENTRY = struct.Struct("<II")
SAMPLE_RATE = 22050
CHANNELS = 1
SAMPLE_WIDTH = 2


@dataclass(frozen=True)
class WaveEntry:
    index: int
    offset: int
    length: int

    @property
    def samples(self) -> int:
        return self.length // SAMPLE_WIDTH

    @property
    def duration(self) -> float:
        return self.samples / SAMPLE_RATE

    @property
    def category(self) -> int:
        return self.index // 100

    def as_dict(self) -> dict:
        return {
            "index": self.index,
            "offset": self.offset,
            "length": self.length,
            "samples": self.samples,
            "duration": round(self.duration, 6),
            "category": self.category,
        }


@dataclass(frozen=True)
class WaveFile:
    entries: tuple[WaveEntry, ...]
    data: bytes

    @property
    def nonzero(self) -> tuple[WaveEntry, ...]:
        return tuple(e for e in self.entries if e.length)

    def as_dict(self) -> dict:
        return {
            "sample_rate": SAMPLE_RATE,
            "channels": CHANNELS,
            "sample_width": SAMPLE_WIDTH,
            "index_size": INDEX_SIZE,
            "entry_count": ENTRY_COUNT,
            "nonzero_count": len(self.nonzero),
            "data_length": len(self.data) - INDEX_SIZE,
            "entries": [e.as_dict() for e in self.entries if e.length],
        }


def parse(blob: bytes) -> WaveFile:
    if len(blob) < INDEX_SIZE:
        raise ValueError(f"WAVE.DAT 太短：{len(blob)} B")
    entries: list[WaveEntry] = []
    expected = 0
    for i in range(ENTRY_COUNT):
        rel, length = ENTRY.unpack_from(blob, i * ENTRY.size)
        # 表尾 1001..1023 是全零占位；中间的 0 长度项 offset 仍指向 expected。
        if rel == 0 and length == 0:
            entries.append(WaveEntry(i, rel, length))
            continue
        if rel != expected:
            raise ValueError(f"WAVE 第 {i} 项 offset={rel}，期望 {expected}")
        if INDEX_SIZE + rel + length > len(blob):
            raise ValueError(f"WAVE 第 {i} 项越过文件尾")
        entries.append(WaveEntry(i, rel, length))
        expected += length
    if INDEX_SIZE + expected != len(blob):
        raise ValueError(
            f"WAVE PCM 区 {expected} B 与文件剩余 {len(blob) - INDEX_SIZE} B 不符"
        )
    return WaveFile(tuple(entries), blob)


def load(path: Path) -> WaveFile:
    return parse(path.read_bytes())


def export_wavs(wave_file: WaveFile, out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for entry in wave_file.nonzero:
        dest = out_dir / f"wave_{entry.index:04d}.wav"
        start = INDEX_SIZE + entry.offset
        payload = wave_file.data[start:start + entry.length]
        with wave.open(str(dest), "wb") as wav:
            wav.setnchannels(CHANNELS)
            wav.setsampwidth(SAMPLE_WIDTH)
            wav.setframerate(SAMPLE_RATE)
            wav.writeframes(payload)
        paths.append(dest)
    return paths
