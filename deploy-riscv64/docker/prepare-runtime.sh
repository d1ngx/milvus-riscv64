#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/deploy-riscv64/rootfs"
BIN_SRC="${ROOT_DIR}/bin/milvus"

SEARCH_DIRS=(
    "${ROOT_DIR}/internal/core/output/lib"
    "${ROOT_DIR}/cmake_build/lib"
    "${ROOT_DIR}/cmake_build/install/lib"
)

if [[ ! -x "${BIN_SRC}" ]]; then
    echo "错误：找不到 Milvus 可执行文件：${BIN_SRC}" >&2
    exit 1
fi

for dir in "${SEARCH_DIRS[@]}"; do
    if [[ ! -d "${dir}" ]]; then
        echo "错误：动态库目录不存在：${dir}" >&2
        exit 1
    fi
done

rm -rf "${OUT_DIR}"
mkdir -p \
    "${OUT_DIR}/bin" \
    "${OUT_DIR}/configs" \
    "${OUT_DIR}/lib"

cp -a "${BIN_SRC}" "${OUT_DIR}/bin/milvus"
cp -a "${ROOT_DIR}/configs/." "${OUT_DIR}/configs/"

# 默认保留调试符号。执行 STRIP_BINARY=1 ./prepare-runtime.sh 可瘦身。
if [[ "${STRIP_BINARY:-0}" == "1" ]]; then
    if ! command -v strip >/dev/null 2>&1; then
        echo "错误：未安装 strip，请先执行：apt install binutils" >&2
        exit 1
    fi

    strip --strip-unneeded "${OUT_DIR}/bin/milvus"
fi

export LD_LIBRARY_PATH="$(
    IFS=:
    echo "${SEARCH_DIRS[*]}"
)"

declare -A SCANNED=()
declare -A COPIED=()
QUEUE=("${BIN_SRC}")

copy_local_library() {
    local src="$1"
    local real
    local base
    local real_base

    [[ -e "${src}" ]] || return 0

    # 只打包 Milvus 工程产生的库；系统库交给 Debian 软件包。
    case "${src}" in
        "${ROOT_DIR}"/*) ;;
        *) return 0 ;;
    esac

    real="$(readlink -f "${src}")"
    base="$(basename "${src}")"
    real_base="$(basename "${real}")"

    if [[ -z "${COPIED[${real}]+x}" ]]; then
        cp -a "${real}" "${OUT_DIR}/lib/${real_base}"
        COPIED["${real}"]=1
        QUEUE+=("${real}")
    fi

    # 保留 SONAME 短名称，例如 librocksdb.so.6 -> librocksdb.so.6.29.5。
    if [[ "${base}" != "${real_base}" ]]; then
        ln -sfn "${real_base}" "${OUT_DIR}/lib/${base}"
    fi
}

while ((${#QUEUE[@]})); do
    current="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")

    real_current="$(readlink -f "${current}")"

    if [[ -n "${SCANNED[${real_current}]+x}" ]]; then
        continue
    fi
    SCANNED["${real_current}"]=1

    while IFS= read -r lib; do
        copy_local_library "${lib}"
    done < <(
        ldd "${real_current}" 2>/dev/null |
        awk '
            /=> \// {print $3}
            /^[[:space:]]*\// {print $1}
        '
    )
done

chmod 0755 "${OUT_DIR}/bin/milvus"

echo
echo "运行文件准备完成：${OUT_DIR}"
echo "Milvus 大小："
du -h "${OUT_DIR}/bin/milvus"

echo
echo "项目动态库数量和大小："
find "${OUT_DIR}/lib" -maxdepth 1 -type f | wc -l
du -sh "${OUT_DIR}/lib"

echo
echo "检查是否误包含静态库："
if find "${OUT_DIR}" -type f -name '*.a' -print -quit | grep -q .; then
    find "${OUT_DIR}" -type f -name '*.a'
    exit 1
else
    echo "未包含 .a 静态库"
fi
