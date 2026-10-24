#!/usr/bin/env bash
# 手动试玩启动器：准备数据/资产后启动游戏，并开启 --playtest 日志。
# F9 导出当前局面；每场结束追加 user://dlz_playtest.jsonl。
set -euo pipefail
cd "$(dirname "$0")"
exec ./run_game.sh -- --playtest
