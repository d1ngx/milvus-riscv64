# Milvus RISC-V 故障排查

本文汇总本次移植和 Standalone 启动过程中遇到的主要问题。

## 1. `curl` 报 OpenSSL 版本不匹配

### 现象

```text
curl: .../internal/core/output/lib/libssl.so.3:
version `OPENSSL_3.2.0' not found
```

### 原因

当前 Shell 全局设置了 Milvus 构建目录的 `LD_LIBRARY_PATH`，导致系统 `curl` 错误加载 Milvus 构建产物中的 `libssl.so.3`。

### 处理

恢复当前 Shell：

```bash
unset LD_LIBRARY_PATH
```

或仅对单次命令清除：

```bash
env -u LD_LIBRARY_PATH curl -sS http://127.0.0.1:2379/health
```

启动 Milvus 时使用仓库脚本：

```bash
./deploy-riscv64/run-with-log.sh
```

不要把 Milvus 动态库路径写入 `/etc/profile`、`~/.bashrc` 或长期 Shell 环境。

## 2. MinIO `signature does not match`

### 现象

```text
The request signature we calculated does not match the signature you provided.
Check your key and signing method.
```

### 原因

Milvus 配置的 Access Key/Secret Key 与 MinIO 实际凭据不一致，或旧 MinIO 数据目录使用了不同配置。

### 处理

当前 Compose 测试凭据：

```text
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
```

Milvus 运行环境：

```bash
MINIO_ACCESS_KEY_ID=minioadmin
MINIO_SECRET_ACCESS_KEY=minioadmin
```

检查容器环境：

```bash
docker inspect milvus-minio \
  --format '{{range .Config.Env}}{{println .}}{{end}}' | \
  grep '^MINIO_'
```

测试环境允许清空时：

```bash
docker compose -f deploy-riscv64/compose.yml down
rm -rf deploy-riscv64/volumes/minio/*
docker compose -f deploy-riscv64/compose.yml up -d
```

修复后正常日志：

```text
blob bucket not exist, create bucket
remote chunk manager init success
```

## 3. MinIO 数据目录权限错误

### 现象

MinIO 容器反复重启，日志包含：

```text
permission denied
file access denied
unable to rename
```

### 原因

Compose 中 MinIO 使用：

```yaml
user: "1000:1000"
```

宿主机挂载目录对 UID/GID 1000 不可写。

### 处理

```bash
mkdir -p deploy-riscv64/volumes/minio
chown -R 1000:1000 deploy-riscv64/volumes/minio
chmod -R u+rwX deploy-riscv64/volumes/minio
```

## 4. 启动早期 `find no available mixcoord`

### 现象

```text
find no available mixcoord, check mixcoord state
node not found[node=0]
bad resolver state
```

### 原因

Standalone 的多个组件并发启动。Proxy、StreamingNode 等可能在 MixCoord 完成注册前尝试连接。

### 判断方法

不要只看最早的警告。继续检查后续日志：

```bash
grep -E 'MixCoord|current state.*Healthy|ready to serve' \
  /root/milvus-riscv64-runtime.log | tail -100
```

如果后续 MixCoord 注册并进入 Healthy，且 Proxy ready，这些属于启动阶段重试。

如果持续数十秒仍无 Healthy，则检查 etcd 中的 session：

```bash
docker exec milvus-etcd \
  /usr/local/bin/etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  get by-dev/meta/session --prefix --keys-only
```

## 5. etcd 旧元数据影响启动

### 现象

- session 指向旧地址或旧节点。
- streaming channel/WAL 分配异常。
- 重建 Milvus 后仍读取旧配置。

### 测试环境清理

仅删除 Milvus 的 `by-dev` 前缀：

```bash
docker exec milvus-etcd \
  /usr/local/bin/etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  del by-dev --prefix
```

完全重建 etcd：

```bash
docker compose -f deploy-riscv64/compose.yml down
rm -rf deploy-riscv64/volumes/etcd/*
docker compose -f deploy-riscv64/compose.yml up -d
```

这些命令会删除元数据，只能用于可丢弃的测试环境。

## 6. etcd 健康检查失败

### 检查容器

```bash
docker compose -f deploy-riscv64/compose.yml ps
docker logs --tail 200 milvus-etcd
```

容器内检查：

```bash
docker exec milvus-etcd \
  /usr/local/bin/etcdctl \
  --endpoints=http://127.0.0.1:2379 \
  endpoint health
```

宿主机端口：

```bash
ss -lntp | grep ':2379\b'
```

Milvus 本体运行在宿主机，因此应使用：

```text
localhost:2379
```

Compose 网络内部服务才使用：

```text
etcd:2379
```

## 7. `bin/milvus` 缺少动态库

### 现象

```text
error while loading shared libraries: libxxx.so: cannot open shared object file
```

### 检查

```bash
ldd bin/milvus | grep 'not found'
```

确认库目录：

```bash
find internal/core/output/lib cmake_build/lib cmake_build/install/lib \
  -name 'libxxx.so*' -print
```

使用启动脚本，或手工只对 Milvus 设置：

```bash
MILVUS_LIB_PATH="$PWD/internal/core/output/lib:$PWD/cmake_build/lib:$PWD/cmake_build/install/lib"
LD_LIBRARY_PATH="$MILVUS_LIB_PATH" ./bin/milvus run standalone
```

## 8. `undefined symbol`

### 原因

通常是运行时加载到了错误版本的第三方库，例如：

- Folly
- Boost.Context
- RocksDB
- OpenSSL
- librdkafka
- milvus-storage

### 检查实际加载路径

```bash
LD_DEBUG=libs \
LD_LIBRARY_PATH="$MILVUS_LIB_PATH" \
./bin/milvus run standalone 2>&1 | tee /tmp/milvus-ld-debug.log
```

检查 RUNPATH：

```bash
readelf -d bin/milvus | grep -E 'RPATH|RUNPATH'
```

检查符号：

```bash
nm -D /path/to/library.so | grep symbol_name
```

## 9. Tantivy/Cargo 长时间无输出

### 判断是否真正卡住

```bash
ps -ef | grep -E 'cargo|rustc' | grep -v grep
```

检查 CPU 和 I/O：

```bash
top -p "$(pgrep -d, -f 'cargo|rustc')"
```

检查最近生成文件：

```bash
find internal/core/thirdparty/tantivy cmake_build \
  -type f -mmin -2 2>/dev/null | tail -50
```

如果 `rustc` 持续占用 CPU，通常仍在编译。RISC-V 原生编译速度可能明显慢于 x86。

## 10. Conan 报 `Invalid setting 'riscv64'`

### 处理

检查：

```bash
conan profile show default
grep -n 'riscv64' ~/.conan/settings.yml
```

在 Conan 1.x `settings.yml` 的 `arch` 中增加 `riscv64`，并确认 compiler version 中包含 GCC 15。

同时确认本分支的：

```text
internal/core/conanfile.py
```

没有继续拒绝该架构。

## 11. pkg-config 指向错误路径

### 现象

编译器找到 `.pc` 文件，但 include 或 lib 指向不存在的 `/usr/local` 或其他架构目录。

### 检查

```bash
pkg-config --variable=prefix rocksdb
pkg-config --cflags --libs rocksdb
pkg-config --cflags --libs rdkafka
```

查看文件来源：

```bash
pkg-config --debug --exists rocksdb 2>&1 | tail -100
```

设置正确的搜索路径：

```bash
export PKG_CONFIG_PATH="/correct/path/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
```

不要把临时生成的 `.pc` 文件提交到仓库根目录。

## 12. Git Push 很慢或失败

本仓库包含完整 Milvus 历史和大量对象，首次推送可能超过 200 MiB。

已验证可使用：

```bash
git push --no-thin -u \
  "https://${GITHUB_TOKEN}@github.com/d1ngx/milvus-riscv64.git" \
  riscv64-v2.6.20
```

安全建议：

- 不要把 Token 写进 Git 配置、脚本、README 或 Shell history。
- 推送后如 Token 曾明文暴露，应立即轮换。
- 后续普通推送直接使用已配置的凭据管理器或 SSH remote。

推荐把 remote 改回无 Token URL：

```bash
git remote set-url origin https://github.com/d1ngx/milvus-riscv64.git
```

## 13. 快速诊断命令

```bash
# Containers
docker compose -f deploy-riscv64/compose.yml ps

# Ports
ss -lntp | grep -E ':(2379|9000|9001|19530|9091)\b'

# Native binary
file bin/milvus
ldd bin/milvus | grep 'not found' || true

# Health
env -u LD_LIBRARY_PATH curl -sS http://127.0.0.1:2379/health
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9000/minio/health/live
env -u LD_LIBRARY_PATH curl -f http://127.0.0.1:9091/healthz

# Fatal errors
grep -nEi \
  'panic|fatal|segmentation fault|illegal instruction|signature.*match|undefined symbol' \
  /root/milvus-riscv64-runtime.log
```
