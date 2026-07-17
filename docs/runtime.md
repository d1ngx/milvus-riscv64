# Milvus RISC-V Standalone 运行说明

本分支使用 Docker Compose 运行 etcd 和 MinIO，Milvus 本体直接运行源码构建出的 `bin/milvus`。

## 1. 运行结构

```text
Host
├── bin/milvus                         # riscv64 native binary
├── deploy-riscv64/run-standalone.sh  # native process launcher
└── Docker
    ├── milvus-etcd                    # port 2379/2380
    └── milvus-minio                   # port 9000/9001
```

## 2. Docker 镜像

`deploy-riscv64/compose.yml` 当前使用：

```text
etcd:latest-riscv64
minio:RELEASE.2024-12-18T13-15-44Z-riscv64
```

确认镜像：

```bash
docker image inspect etcd:latest-riscv64
docker image inspect minio:RELEASE.2024-12-18T13-15-44Z-riscv64
```

## 3. 初始化数据目录

```bash
mkdir -p deploy-riscv64/volumes/{etcd,minio}
chown -R 1000:1000 deploy-riscv64/volumes/minio
```

MinIO 容器以 `1000:1000` 运行，因此挂载目录必须可写。

## 4. 启动依赖服务

```bash
docker compose -f deploy-riscv64/compose.yml up -d
docker compose -f deploy-riscv64/compose.yml ps
```

查看日志：

```bash
docker compose -f deploy-riscv64/compose.yml logs -f etcd minio
```

停止：

```bash
docker compose -f deploy-riscv64/compose.yml down
```

完全清空测试数据：

```bash
docker compose -f deploy-riscv64/compose.yml down
rm -rf deploy-riscv64/volumes/etcd/*
rm -rf deploy-riscv64/volumes/minio/*
```

该操作会永久删除测试元数据和对象数据。

## 5. 环境变量

`deploy-riscv64/env-riscv64.sh` 定义：

```bash
ETCD_ENDPOINTS=localhost:2379
MINIO_ADDRESS=localhost
MINIO_PORT=9000
MINIO_ACCESS_KEY_ID=minioadmin
MINIO_SECRET_ACCESS_KEY=minioadmin
```

以及 Milvus 需要的本地动态库目录：

```text
internal/core/output/lib
cmake_build/lib
cmake_build/install/lib
```

查看配置：

```bash
source deploy-riscv64/env-riscv64.sh
```

该脚本只生成 `MILVUS_LIB_PATH`，不会直接覆盖当前 Shell 的 `LD_LIBRARY_PATH`。

## 6. 启动 Milvus

直接启动：

```bash
chmod +x deploy-riscv64/*.sh
./deploy-riscv64/run-standalone.sh
```

同时保存日志：

```bash
./deploy-riscv64/run-with-log.sh
```

默认日志文件由 `run-with-log.sh` 决定。也可以覆盖：

```bash
LOG_FILE=/root/milvus-riscv64-runtime.log \
  ./deploy-riscv64/run-with-log.sh
```

启动脚本会：

1. 计算仓库根目录。
2. 读取 etcd、MinIO 和动态库配置。
3. 删除遗留的 `/run/milvus/standalone.pid`。
4. 只对 Milvus 子进程设置 `LD_LIBRARY_PATH`。
5. 执行 `bin/milvus run standalone`。

## 7. 等价的完整手工命令

需要调试脚本时，可使用：

```bash
cd /root/gits/milvus

MILVUS_LIB_PATH="\
$PWD/internal/core/output/lib:\
$PWD/cmake_build/lib:\
$PWD/cmake_build/install/lib"

rm -f /run/milvus/standalone.pid

LD_LIBRARY_PATH="$MILVUS_LIB_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
ETCD_ENDPOINTS=localhost:2379 \
MINIO_ADDRESS=localhost \
MINIO_PORT=9000 \
MINIO_ACCESS_KEY_ID=minioadmin \
MINIO_SECRET_ACCESS_KEY=minioadmin \
./bin/milvus run standalone
```

不要把上述 `LD_LIBRARY_PATH` 全局 export 到长期使用的 Shell。

## 8. 健康检查

当 Shell 曾设置过 `LD_LIBRARY_PATH` 时，检查系统服务应显式清除：

```bash
env -u LD_LIBRARY_PATH curl -sS http://127.0.0.1:2379/health
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9000/minio/health/live
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9091/healthz
```

检查容器内部 etcd：

```bash
docker exec milvus-etcd \
  /usr/local/bin/etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  endpoint health
```

检查端口：

```bash
ss -lntp | grep -E ':(19530|19529|9091|21123|21124|22125|22222)\b'
```

主要端口：

| Port | Purpose |
| --- | --- |
| 19530 | Milvus client/API |
| 19529 | internal Proxy gRPC |
| 9091 | management/health |
| 21123 | QueryNode |
| 21124 | DataNode |
| 22125 | MixCoord |
| 22222 | StreamingNode |
| 2379 | etcd client |
| 9000 | MinIO S3 API |
| 9001 | MinIO console |

## 9. 日志成功标志

```bash
grep -E \
  'remote chunk manager init success|current state.*Healthy|ready to serve|successfully initialized' \
  /root/milvus-riscv64-runtime.log | tail -100
```

对象存储正常时可看到：

```text
blob bucket not exist, create bucket
remote chunk manager init success
```

首次空数据启动时，Milvus 会创建 `a-bucket`。

## 10. 停止 Milvus

前台运行时使用 `Ctrl+C`。

后台运行时先找到 PID：

```bash
cat /run/milvus/standalone.pid
```

然后正常终止：

```bash
kill -TERM "$(cat /run/milvus/standalone.pid)"
```

不要直接删除运行中的数据目录。
