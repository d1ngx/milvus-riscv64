FROM debian:13-slim

ARG MILVUS_VERSION=2.6.20-riscv64
ARG BUILD_DATE=""
ARG VCS_REF=""
ARG DEBIAN_MIRROR=mirrors.ustc.edu.cn

LABEL org.opencontainers.image.title="Milvus RISC-V" \
      org.opencontainers.image.version="${MILVUS_VERSION}" \
      org.opencontainers.image.source="https://github.com/d1ngx/milvus-riscv64" \
      org.opencontainers.image.description="Milvus 2.6.20 standalone runtime image for Linux riscv64" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    ETCD_ENDPOINTS=etcd:2379 \
    MINIO_ADDRESS=minio \
    MINIO_PORT=9000 \
    MINIO_ACCESS_KEY_ID=minioadmin \
    MINIO_SECRET_ACCESS_KEY=minioadmin

# Debian 13 容器默认使用 DEB822 格式的软件源。
# 切换为中科大 Debian 和 Debian Security 国内镜像。
RUN printf '%s\n' \
    'Types: deb' \
    "URIs: http://${DEBIAN_MIRROR}/debian" \
    'Suites: trixie trixie-updates' \
    'Components: main contrib non-free non-free-firmware' \
    'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
    '' \
    'Types: deb' \
    "URIs: http://${DEBIAN_MIRROR}/debian-security" \
    'Suites: trixie-security' \
    'Components: main contrib non-free non-free-firmware' \
    'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
    > /etc/apt/sources.list.d/debian.sources && \
    rm -f /etc/apt/sources.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        tzdata \
        libatomic1 \
        libgcc-s1 \
        libgomp1 \
        libstdc++6 \
        libaio1t64 \
        libunwind8 \
        libgfortran5 \
        libopenblas0-pthread \
        zlib1g \
        liblz4-1 \
        libzstd1 \
        libsnappy1v5 \
        libuuid1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 milvus \
    && useradd \
        --system \
        --uid 10001 \
        --gid milvus \
        --home-dir /var/lib/milvus \
        --shell /usr/sbin/nologin \
        milvus \
    && mkdir -p \
        /milvus/bin \
        /milvus/configs \
        /milvus/lib \
        /milvus/logs \
        /var/lib/milvus \
        /run/milvus \
    && chown -R milvus:milvus \
        /milvus \
        /var/lib/milvus \
        /run/milvus

WORKDIR /milvus

COPY --chown=milvus:milvus deploy-riscv64/rootfs/bin/milvus /milvus/bin/milvus
COPY --chown=milvus:milvus deploy-riscv64/rootfs/configs/ /milvus/configs/
COPY --chown=milvus:milvus deploy-riscv64/rootfs/lib/ /milvus/lib/
COPY --chown=milvus:milvus deploy-riscv64/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 \
        /milvus/bin/milvus \
        /usr/local/bin/docker-entrypoint.sh

VOLUME ["/var/lib/milvus"]

EXPOSE 19530 19529 9091

HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=120s \
    --retries=5 \
    CMD ["curl", "-fsS", "http://127.0.0.1:9091/healthz"]

USER milvus

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["run", "standalone"]
