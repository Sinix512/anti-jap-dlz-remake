"""重建 HZK16 BMFont：扫描全部 Godot 脚本与生成数据。

新增 UI/剧情文案后必须跑一次，否则 HZK16 字库缺字会显示方框。
用法：
    python3 tools/rebuild_font.py
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "godot"
DATA = GODOT / "data"


def main() -> None:
    spec = importlib.util.spec_from_file_location(
        "prepare_m1", ROOT / "tools" / "prepare_m1.py")
    m1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m1)
    texts: list[str] = []
    for p in sorted(DATA.glob("*.json")):
        if p.name == "gbk_codec.json":
            continue
        try:
            texts.append(p.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            pass
    for p in sorted((GODOT / "scripts").rglob("*.gd")):
        texts.append(p.read_text(encoding="utf-8"))
    # 常用但可能只出现在数据字符串里的符号
    texts.append("★☆·—…“”‘’《》〈〉「」【】〔〕％＋－×÷")
    glyphs, atlas = m1.build_font(texts)
    print("font", glyphs, "glyphs", atlas)


if __name__ == "__main__":
    main()
