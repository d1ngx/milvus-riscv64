#!/bin/sh
set -eu

export LD_LIBRARY_PATH="/milvus/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

if [ "$#" -eq 0 ]; then
    set -- run standalone
fi

# 兼容直接传入 "run standalone"
case "$1" in
    run|help|--help|-h|version|--version)
        set -- /milvus/bin/milvus "$@"
        ;;
esac

exec "$@"
