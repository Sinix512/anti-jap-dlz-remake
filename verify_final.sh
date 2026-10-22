#!/usr/bin/env bash
# 最终验收：数据/UI 回归 + 资产审计 + 三档难度 47 关全通。
set -euo pipefail
cd "$(dirname "$0")"
./verify_all.sh
./verify_play.sh
echo "FINAL_ACCEPTANCE_OK"
