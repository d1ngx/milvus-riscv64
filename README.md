# Milvus 2.6.20 on RISC-V 64

本仓库记录并保存 Milvus v2.6.20 在 `linux/riscv64` 上的源码适配、构建与 standalone 运行环境。

## 已验证环境

- Milvus: `v2.6.20`
- Git commit: `65db4ea`
- Go: `go1.26.0 linux/riscv64`
- GCC: `15`
- Conan: `1.66.0`
- etcd: 本地镜像 `etcd:latest-riscv64`
- MinIO: 本地镜像 `minio:RELEASE.2024-12-18T13-15-44Z-riscv64`
- 消息队列: `rocksmq`
- 构建产物: `bin/milvus`
- 可执行文件类型: ELF 64-bit RISC-V，RVC，double-float ABI

## 本次适配内容

### Go 层

1. 禁用 `bytedance/sonic` 构建标签，避免 riscv64 不支持。
2. `internal/json/sonic.go` 改用 Go 标准库 `encoding