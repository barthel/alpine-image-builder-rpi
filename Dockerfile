FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    binfmt-support \
    qemu-user-static \
    parted \
    dosfstools \
    e2fsprogs \
    util-linux \
    kpartx \
    zip \
    unzip \
    wget \
    ca-certificates \
    file \
    shellcheck \
    ruby-full \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && gem install serverspec --no-document

COPY builder /builder/

CMD ["/builder/build.sh"]
