# Milvus 2.6.20 RISC-V 移植修改记录

本文总结本分支为 `linux/riscv64` 所做的主要源码、构建系统和运行时适配。

## 1. 修改文件

当前核心修改集中在：

```text
Makefile
internal/core/conanfile.py
internal/core/src/exec/expression/SimdFilter.cpp
internal/core/src/storage/LocalChunkManager.h
internal/json/sonic.go
scripts/3rdparty_build.sh
```

此外，本地构建过程中还涉及 Conan profile/settings、pkg-config 文件、Folly/Boost.Context 和其他第三方依赖的生成配置。这些本机生成文件不应直接提交为源码修改。

## 2. Sonic / JSON

### 问题

Sonic 包含针对特定架构的汇编和运行时优化路径，在 RISC-V 上无法直接按原构建方式使用。

### 处理

- 调整 `Makefile`，避免在 RISC-V 构建中启用 Sonic 相关构建标签或依赖。
- 调整 `internal/json/sonic.go`，使 RISC-V 使用兼容的标准 JSON 实现。
- 保持 Milvus 内部 JSON 接口不变，减少对上层代码的影响。

### 影响

功能兼容优先于特定架构 JSON 加速。RISC-V 上的 JSON 性能需要后续单独评估。

## 3. Conan 架构支持

### 问题

Milvus 2.6.20 的核心依赖配置原先主要覆盖 x86/x86_64 等架构，`internal/core/conanfile.py` 对架构值有限制；本机 Conan 1.x 的 `settings.yml` 也可能没有 GCC 15 或 `riscv64`。

### 处理

- 在 `internal/core/conanfile.py` 中允许 `riscv64`。
- 本机 Conan profile 设置：

```ini
os=Linux
arch=riscv64
compiler=gcc
compiler.version=15
compiler.libcxx=libstdc++11
build_type=Release
```

- 必要时在 `~/.conan/settings.yml` 增加 `riscv64` 和 GCC 15。

### 原则

仓库仅提交 Milvus 自身必要修改；用户目录中的 Conan 配置通过文档说明，不把本机配置硬编码进源码。

## 4. SIMD / RVV

### 问题

`SimdFilter.cpp` 和相关构建逻辑包含 x86 SIMD 假设、编译器 intrinsic 或动态 SIMD 分派路径。RISC-V 编译器无法直接处理这些路径。

### 处理

- 调整 `internal/core/src/exec/expression/SimdFilter.cpp` 的条件编译。
- 避免 RISC-V 进入仅适用于 x86 的 SIMD 分支。
- 初次构建使用：

```text
USE_DYNAMIC_SIMD=OFF
```

### 当前状态

Knowhere 可在 RISC-V 上初始化并列出可用索引。后续可继续针对 RVV 做性能优化，但当前分支优先保证正确构建和运行。

## 5. LocalChunkManager

### 问题

RISC-V 工具链和头文件依赖检查更严格，`LocalChunkManager.h` 的间接 include 依赖会导致编译失败。

### 处理

在 `internal/core/src/storage/LocalChunkManager.h` 中补齐或修正所需头文件依赖，避免依赖其他文件的偶然 include 顺序。

## 6. 第三方依赖构建

`scripts/3rdparty_build.sh` 已针对 RISC-V 构建流程调整。实际移植中处理过以下依赖：

- Folly
- Boost.Context
- RocksDB
- librdkafka
- milvus-storage
- Tantivy/Rust
- goZapLogExt
- pkg-config metadata

### Folly / Boost.Context

Boost.Context 和 Folly 的协程/上下文实现通常包含架构相关汇编。RISC-V 需要选择可用的上下文后端，或避免链接到不存在的 x86 实现。

本次处理重点包括：

- 修正 Folly 配置发现。
- 修正 Boost.Context/ucontext 相关链接。
- 修正最终二进制的 RUNPATH 和动态库解析。

### RocksDB / librdkafka / milvus-storage

主要处理：

- Conan 包架构限制。
- 编译参数不兼容。
- pkg-config 中错误的 include/lib 路径。
- 构建产物位于 `cmake_build` 或 `internal/core/output`，但 `.pc` 文件仍指向其他前缀的问题。

## 7. pkg-config

移植过程中重点检查过：

```text
milvus-storage.pc
milvus_core.pc
rocksdb.pc
rdkafka.pc
libfolly.pc
```

排查命令：

```bash
pkg-config --cflags --libs <package>
pkg-config --variable=prefix <package>
```

确保输出路径指向当前构建目录，而不是不存在或架构不匹配的 `/usr/local` 产物。

## 8. 动态库与 RUNPATH

### 问题

最终 Go/CGO 二进制需要加载 Milvus C++ 核心及第三方动态库。RISC-V 本地构建中可能同时存在：

```text
internal/core/output/lib
cmake_build/lib
cmake_build/install/lib
```

错误的 RPATH/RUNPATH 会导致：

```text
error while loading shared libraries
not found
undefined symbol
```

### 处理

运行时脚本组合上述目录，并仅为 Milvus 子进程设置 `LD_LIBRARY_PATH`。

### 安全注意

构建目录中可能有自己的 OpenSSL：

```text
internal/core/output/lib/libssl.so.3
```

如果全局导出该目录，系统 `curl` 可能报：

```text
version `OPENSSL_3.2.0' not found
```

因此禁止把 Milvus 动态库路径长期写入全局 Shell 环境。

## 9. Standalone 运行环境

新增：

```text
deploy-riscv64/compose.yml
deploy-riscv64/env-riscv64.sh
deploy-riscv64/run-standalone.sh
deploy-riscv64/run-with-log.sh
```

设计原则：

- etcd 和 MinIO 使用 RISC-V Docker 镜像。
- Milvus 使用源码构建的本机二进制。
- etcd 暴露 `2379` 给宿主机 Milvus。
- MinIO 暴露 `9000`，凭据固定为测试用 `minioadmin/minioadmin`。
- 数据保存在 `deploy-riscv64/volumes`，该目录不提交。

## 10. 已验证启动流程

日志已验证以下关键路径：

```text
create etcd client
config atomically saved to etcd
blob bucket not exist, create bucket
remote chunk manager init success
MixCoord healthy
Proxy ready to serve
```

启动早期出现短暂的：

```text
find no available mixcoord
bad resolver state
```

通常是组件并发启动、MixCoord 尚未注册完成时的重试日志。应结合后续是否进入 Healthy 判断，不能只看最早几行警告。

## 11. 当前限制

- 该移植以 Standalone 正确运行优先。
- 尚未声明所有索引类型均完成性能和正确性测试。
- 动态 SIMD 已关闭。
- Disk index 在初次移植中关闭。
- 使用的 etcd/MinIO RISC-V 镜像为本地镜像名，其他用户需要自行构建或替换。
- 尚未完成上游可接受形式的最小化 patch 拆分。

## 12. 后续建议

1. 对主要向量索引运行单元测试和 benchmark。
2. 验证 RVV 优化路径，逐步替代通用实现。
3. 将第三方依赖修复拆分为可复用 patch。
4. 固定可复现的容器镜像构建文件和版本。
5. 在 RISC-V CI 或自托管 Runner 上自动构建。
6. 对比 upstream `v2.6.20`，整理最小 diff 并尝试上游提交。
