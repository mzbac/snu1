FROM ubuntu:22.04@sha256:0d779ea97881505f5ef0039336ee85edba27519bdba968c284c86ee066a973c8

ARG SNU1_VERSION="unknown"
ARG SNU1_REVISION="unknown"
ARG SNU1_RELEASE_URL="https://github.com/mzbac/snu1/releases"

LABEL org.opencontainers.image.title="snu1" \
      org.opencontainers.image.description="Native SenseNova-U1 image generation and editing server for NVIDIA Ada SM89 GPUs" \
      org.opencontainers.image.source="https://github.com/mzbac/snu1" \
      org.opencontainers.image.url="${SNU1_RELEASE_URL}" \
      org.opencontainers.image.version="${SNU1_VERSION}" \
      org.opencontainers.image.revision="${SNU1_REVISION}"
COPY snu1 /usr/local/bin/snu1

ENV HOME=/tmp \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    NVIDIA_REQUIRE_CUDA="cuda>=12.8"

EXPOSE 8080
USER 65532:65532
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD ["/bin/bash", "-ec", "exec 3<>/dev/tcp/127.0.0.1/8080; printf 'GET /healthz HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3; IFS=' ' read -r proto status rest <&3; test \"$proto\" = HTTP/1.1; test \"$status\" = 200"]

ENTRYPOINT ["/usr/local/bin/snu1"]
CMD ["serve", "--model_path", "/models/base.gguf", "--lora_path", "/models/lora.gguf", "--host", "0.0.0.0", "--port", "8080", "--allow-remote"]
