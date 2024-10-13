#!/bin/bash

### Install Docker
apt-get update -y
apt-get install -y curl ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

echo -e '{\n  "storage-driver": "overlay2"\n  "bridge": "none"\n}' >> /etc/docker/daemon.json

### Populate arguments
secrets_list=()
for arg in "$@"; do
    secrets_list+=$'      - "--set"\n      - "'"$arg"$'"\n'
done

# Create compose file for auroraboot
cat << EOF > /root/docker-compose.yml
version: "3.8"
services:
  auroraboot:
    image: quay.io/kairos/auroraboot
    container_name: auroraboot
    restart: unless-stopped
    network_mode: host
    command:
      - "https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/auroraboot-config.yaml"
      - "--cloud-config"
      - "https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/cloud-config.yaml"
      - "--set"
      - "P2P_NETWORK_TOKEN=$(docker run -ti --rm quay.io/mudler/edgevpn -b -g)"
${secrets_list[@]}
    volumes:
      - ./auroraboot:/storage
EOF

cd /root
mkdir -p /root/auroraboot
docker compose up -d
while ! echo exit | nc localhost 8081; do sleep 10; done