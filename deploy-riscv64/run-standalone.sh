#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MILVUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/env-riscv64.sh"

cd "${MILVUS_ROOT}"

rm -f /run/milvus/standalone.pid

exec env \
  LD_LIBRARY_PATH="${MILVUS_LIB_PATH}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  ETCD_ENDPOINTS="${ETCD_ENDPOINTS}" \
  MINIO_ADDRESS="${MINIO_ADDRESS}" \
  MINIO_PORT="${MINIO_PORT}" \
  MINIO_ACCESS_KEY_ID="${MINIO_ACCESS_KEY_ID}" \
  MINIO_SECRET_ACCESS_KEY="${MINIO_SECRET_ACCESS_KEY}" \
  "${MILVUS_ROOT}/bin/milvus" run standalone
