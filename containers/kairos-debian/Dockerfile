FROM quay.io/kairos/debian:bookworm-standard-amd64-generic-v3.2.1-k3sv1.29.9-k3s1

ARG IMAGE_TAG

# renovate: datasource=github-tags depName=fluxcd/flux2
ENV FLUX_VERSION="v2.2.3"

ADD https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz /tmp
RUN DOWNLOAD_FILE="/tmp/flux_${FLUX_VERSION}_linux_amd64.tar.gz" && \
    tar xzf "${DOWNLOAD_FILE}" -C /usr/bin flux && \
    rm "${DOWNLOAD_FILE}"

RUN apt-get update && \
    apt-get install -y \
    git \
    && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ADD ./units /etc/systemd/system/

RUN systemctl enable \
    k3s-agent-ready.service \
    k3s-ready.service

RUN echo "KAIROS_CUSTOM_BUILD_TAG=$IMAGE_TAG" >> /etc/os-release