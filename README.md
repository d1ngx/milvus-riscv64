# Milvus 2.6.20 for RISC-V 64

本仓库基于 Milvus `v2.6.20`，记录并保存可在 Linux `riscv64` 上构建和运行 Milvus Standalone 的源码修改、依赖处理方案与运行环境。

> 当前重点是源码构建与 Standalone 验证。etcd 和 MinIO 使用本地 RISC-V Docker 镜像，Milvus 本体直接运行源码构建出的 `bin/milvus`。

## 当前状态

- Milvus 版本：`2.6.20`
- 架构：`linux/riscv64`
- Go：`go1.26.0 linux/riscv64`
- 编译器：GCC 15
- 消息队列：Rocksmq
- 元数据：etcd
- 对象存储：MinIO
- 已验证：Milvus Standalone 可启动，MinIO bucket 可自动创建，Proxy、MixCoord、StreamingNode 等组件可进入可服务状态

## 仓库结构

```text
milvus-riscv64/
├── README.md
├── docs/
│   ├── build.md
│   ├── runtime.md
│   ├── riscv64-porting.md
│   └── troubleshooting.md
├── deploy-riscv64/
│   ├── compose.yml
│   ├── env-riscv64.sh
│   ├── run-standalone.sh
│   └── run-with-log.sh
└── ... Milvus source tree
```

## 快速开始

### 1. 切换分支

```bash
git clone -b riscv64-v2.6.20 \
  https://github.com/d1ngx/milvus-riscv64.git
cd milvus-riscv64
```

### 2. 启动 etcd 和 MinIO

当前 Compose 引用以下本地 RISC-V 镜像：

```text
etcd:latest-riscv64
minio:RELEASE.2024-12-18T13-15-44Z-riscv64
```

确认镜像存在：

```bash
docker image inspect etcd:latest-riscv64
docker image inspect minio:RELEASE.2024-12-18T13-15-44Z-riscv64
```

准备数据目录并启动：

```bash
mkdir -p deploy-riscv64/volumes/{etcd,minio}
chown -R 1000:1000 deploy-riscv64/volumes/minio

docker compose -f deploy-riscv64/compose.yml up -d
docker compose -f deploy-riscv64/compose.yml ps
```

### 3. 构建 Milvus

构建环境及第三方依赖说明见 [docs/build.md](docs/build.md)。完成依赖准备后执行：

```bash
make build-go
```

确认产物：

```bash
file bin/milvus
ldd bin/milvus
```

### 4. 启动 Milvus

```bash
chmod +x deploy-riscv64/*.sh
./deploy-riscv64/run-with-log.sh
```

环境变量由 `deploy-riscv64/env-riscv64.sh` 提供，动态库路径只传给 Milvus 进程，不污染当前 Shell。

### 5. 健康检查

在另一个终端执行：

```bash
env -u LD_LIBRARY_PATH curl -sS http://127.0.0.1:2379/health
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9000/minio/health/live
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9091/healthz
```

端口检查：

```bash
ss -lntp | grep -E ':(19530|19529|9091|21123|21124|22125|22222)\b'
```

## 文档

- [构建说明](docs/build.md)
- [运行与环境变量](docs/runtime.md)
- [RISC-V 移植修改](docs/riscv64-porting.md)
- [故障排查](docs/troubleshooting.md)

## 主要源码修改

本分支主要修改了：

```text
Makefile
internal/core/conanfile.py
internal/core/src/exec/expression/SimdFilter.cpp
internal/core/src/storage/LocalChunkManager.h
internal/json/sonic.go
scripts/3rdparty_build.sh
```

主要处理内容包括：

- 为 Conan 和第三方构建流程增加 `riscv64` / GCC 15 支持
- 在 RISC-V 上禁用或替换不兼容的 Sonic 路径
- 修复 SIMD/RVV 条件编译
- 修复本地存储头文件依赖
- 修复 Folly、Boost.Context、RocksDB、librdkafka、milvus-storage 等第三方依赖构建和链接
- 调整 pkg-config、RUNPATH 和动态库搜索路径
- 提供 etcd/MinIO Compose 与 Milvus Standalone 启动脚本

## 重要说明

不要在当前 Shell 中长期执行：

```bash
export LD_LIBRARY_PATH=/path/to/milvus/libs
```

Milvus 构建目录可能包含自己的 `libssl.so.3`。全局设置后，系统 `curl`、`git` 等程序可能错误加载该库并出现版本不匹配。请使用仓库提供的启动脚本，只把 `LD_LIBRARY_PATH` 传给 Milvus 子进程。

## 上游项目

本仓库是 Milvus 的 RISC-V 适配分支。Milvus 原项目、许可证和社区信息请参阅：

- Milvus upstream: https://github.com/milvus-io/milvus
- Milvus documentation: https://milvus.io/docs
- License: [LICENSE](LICENSE)
