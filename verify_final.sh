#!/usr/bin/env bash
# 严格最终门槛：未证明正常成长47关前必须非零退出，不复用旧作弊bot结论。
set -euo pipefail
cd "$(dirname "$0")"
./verify_original.sh --ui --legal --require-campaign
echo "ORIGINAL_FINAL_ACCEPTANCE_OK"
