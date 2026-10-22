#!/usr/bin/env bash
# M3-M6 一键准备：UI 资产、47 关数据、剧情/结局、字库，然后启动 Godot。
set -euo pipefail
cd "$(dirname "$0")"
python3 tools/prepare_m1.py
python3 tools/prepare_m2.py
python3 tools/prepare_m3.py
python3 tools/prepare_bgm.py
python3 tools/prepare_m4.py
python3 tools/prepare_m5.py
python3 tools/rebuild_font.py
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT_BIN" --headless --path godot --editor --quit >/dev/null
exec "$GODOT_BIN" --path godot "$@"
