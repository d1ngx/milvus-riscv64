#!/usr/bin/env bash

# This file is intended to be sourced:
#   source deploy-riscv64/env-riscv64.sh

MILVUS_ROOT="${MILVUS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-localhost:2379}"

export MINIO_ADDRESS="${MINIO_ADDRESS:-localhost}"
export MINIO_PORT="${MINIO_PORT:-9000}"
export MINIO_ACCESS_KEY_ID="${MINIO_ACCESS_KEY_ID:-minioadmin}"
export MINIO_SECRET_ACCESS_KEY="${MINIO_SECRET_ACCESS_KEY:-minioadmin}"

export MILVUS_LIB_PATH="\
${MILVUS_ROOT}/internal/core/output/lib:\
${MILVUS_ROOT}/cmake_build/lib:\
${MILVUS_ROOT}/cmake_build/install/lib"

echo "MILVUS_ROOT=${MILVUS_ROOT}"
echo "ETCD_ENDPOINTS=${ETCD_ENDPOINTS}"
echo "MINIO_ADDRESS=${MINIO_ADDRESS}:${MINIO_PORT}"
echo "MILVUS_LIB_PATH=${MILVUS_LIB_PATH}"
