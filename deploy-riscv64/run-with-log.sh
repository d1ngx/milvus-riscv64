#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/milvus-riscv64-runtime.log}"

set -o pipefail
"${SCRIPT_DIR}/run-standalone.sh" 2>&1 | tee "${LOG_FILE}"
