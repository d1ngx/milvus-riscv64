# Milvus 2.6.20 RISC-V 构建说明

本文记录本分支在 Linux `riscv64` 上构建 Milvus 2.6.20 的环境、主要步骤和验证方式。

## 1. 已验证环境

```text
Architecture: riscv64
Milvus:      v2.6.20
Go:          1.26.0
GCC:         15
Conan:       1.66.0
Build type:  Release
SIMD:        USE_DYNAMIC_SIMD=OFF
Disk index:  disabled during the initial port
```

不同发行版的软件包名称可能不同，但至少需要：

- GCC/G++ 15 或可用的 RISC-V C/C++ 工具链
- Go 1.26
- CMake
- Ninja 或 Make
- Python 3
- Conan 1.x
- pkg-config
- Rust/Cargo（Tantivy）
- Git、curl、patch、autoconf、automake、libtool

## 2. 获取源码

```bash
git clone -b riscv64-v2.6.20 \
  https://github.com/d1ngx/milvus-riscv64.git
cd milvus-riscv64
```

确认架构：

```bash
uname -m
gcc --version
go version
cmake --version
conan --version
```

预期 `uname -m` 输出：

```text
riscv64
```

## 3. Conan 配置

本分支已修改 `internal/core/conanfile.py` 以允许 `riscv64`。本机 Conan 配置仍需包含对应架构和编译器版本。

示例 profile：

```ini
[settings]
os=Linux
arch=riscv64
compiler=gcc
compiler.version=15
compiler.libcxx=libstdc++11
build_type=Release

[options]

[build_requires]

[env]
CC=gcc
CXX=g++
```

查看当前 profile：

```bash
conan profile show default
```

如果 Conan 1.x 的 `settings.yml` 尚未包含 `riscv64` 或 GCC 15，需要在用户 Conan 配置中补充对应值。配置文件通常位于：

```text
~/.conan/settings.yml
```

## 4. 构建第三方依赖

本分支修改了 `scripts/3rdparty_build.sh`，用于处理 RISC-V 上的部分第三方依赖差异。

执行：

```bash
./scripts/3rdparty_build.sh
```

首次构建耗时较长，Tantivy/Rust、Folly、RocksDB 等步骤可能长时间占用 CPU。

可在另一个终端确认构建是否仍在进行：

```bash
ps -ef | grep -E 'cargo|rustc|cmake|ninja|make|conan' | grep -v grep
```

检查是否仍有文件写入：

```bash
find cmake_build internal/core/output \
  -type f -mmin -2 2>/dev/null | tail
```

## 5. 关键构建选项

初次移植建议关闭 x86 动态 SIMD 分派和磁盘索引：

```bash
export USE_DYNAMIC_SIMD=OFF
export DISK_INDEX_BUILD_VERSION=OFF
```

具体变量是否由当前 Makefile/CMake 直接读取，应以本分支脚本为准。查看最终 CMake 缓存：

```bash
grep -E 'USE_DYNAMIC_SIMD|DISK_INDEX|CMAKE_BUILD_TYPE|CMAKE_CXX_COMPILER' \
  cmake_build/CMakeCache.txt
```

## 6. 编译 Milvus

完成第三方依赖后执行：

```bash
make build-go
```

也可以保留完整日志：

```bash
set -o pipefail
make build-go 2>&1 | tee /tmp/milvus-riscv64-build.log
```

## 7. 验证产物

```bash
file bin/milvus
readelf -h bin/milvus | grep -E 'Class|Machine'
ldd bin/milvus
```

预期应看到 RISC-V 64 位 ELF。

检查缺失库：

```bash
ldd bin/milvus | grep 'not found' || true
```

检查需要的动态库目录：

```bash
find internal/core/output/lib cmake_build/lib cmake_build/install/lib \
  -maxdepth 1 -type f -o -type l 2>/dev/null | head
```

## 8. 不要提交构建产物

以下内容属于本地构建或调试产物，不应提交到 Git：

```text
cmake_build.before-*/
internal/core/output.before-*/
folly/
*.bak
*.bak.*
deploy-riscv64/volumes/
*.log
```

提交前检查：

```bash
git status --short
git diff --cached --name-only | \
  grep -E '(^|/)(cmake_build|output\.before|volumes|folly)(/|$)|\.bak' || true
```

## 9. 构建完成后的下一步

构建成功后不要直接全局导出动态库路径。使用：

```bash
./deploy-riscv64/run-with-log.sh
```

完整运行说明见 [runtime.md](runtime.md)。
