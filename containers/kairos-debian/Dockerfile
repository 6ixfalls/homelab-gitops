FROM quay.io/kairos/debian:bookworm-standard-amd64-generic-v3.2.1-k3sv1.31.1-k3s1

# renovate: datasource=github-releases depName=fluxcd/flux2
ENV FLUX_VERSION=2.2.3

ADD https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz /tmp
RUN DOWNLOAD_FILE="/tmp/flux_${FLUX_VERSION}_linux_amd64.tar.gz" && \
    tar xzf "${DOWNLOAD_FILE}" -C /usr/bin flux && \
    rm "${DOWNLOAD_FILE}"

RUN apt-get update && \
    apt-get install -y \
    git \
    && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN kernel=$(ls /lib/modules | head -n1) && \
    dracut -v -f "/boot/initrd-${kernel}" "${kernel}" && \
    ln -sf "initrd-${kernel}" /boot/initrd && \
    kernel=$(ls /lib/modules | head -n1) && \
    depmod -a "${kernel}"