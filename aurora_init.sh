#!/bin/bash

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

cat << EOF > /root/aurora-entrypoint.sh
#!/bin/bash

declare -A variables=(
    [p2p_network_token]=$P2P_NETWORK_TOKEN
    [doppler_token]=$DOPPLER_TOKEN
    [doppler_project]=$DOPPLER_PROJECT
    [cluster_domain]=$CLUSTER_DOMAIN
)

#base64 encode needed
variables[doppler_token]=$(echo -n ${variables[doppler_token]} | base64 -w0)
variables[doppler_project]=$(echo -n ${variables[doppler_project]} | base64 -w0)
variables[cluster_domain]=$(echo -n ${variables[cluster_domain]} | base64 -w0)

curl -o /tmp/pulled-cloud-config.yaml https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/cloud-config.yaml
sed_command="sed"

# Dynamically build the sed command based on the variables
for key in "${!variables[@]}"; do
    value=${variables[$key]}
    # Escape slashes in the value
    escaped_value=$(echo $value | sed 's/\//\\\//g')
    sed_command+=" -e 's/{{ ${key^^} }}/${escaped_value}/g'"
done

# Apply the transformations
sed_command+=" /tmp/pulled-cloud-config.yaml > /tmp/cloud-config.yaml"
eval $sed_command

/usr/bin/auroraboot --cloud-config /tmp/cloud-config.yaml https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/cloud-config.yaml
EOF
chmod +x /root/aurora-entrypoint.sh

# Create compose file for auroraboot
cat << EOF > /root/docker-compose.yml
version: "3.8"
services:
  auroraboot:
    image: quay.io/kairos/auroraboot
    container_name: auroraboot
    restart: unless-stopped
    network_mode: host
    environment:
      P2P_NETWORK_TOKEN: "$(docker run -ti --rm quay.io/mudler/edgevpn -b -g)"
      DOPPLER_TOKEN: "$DOPPLER_TOKEN"
      DOPPLER_PROJECT: "$DOPPLER_PROJECT"
      CLUSTER_DOMAIN: "$CLUSTER_DOMAIN"
    entrypoint: bash
    command: -c "/usr/bin/aurora-entrypoint.sh"
    volumes:
      - /root/aurora-entrypoint.sh:/usr/bin/aurora-entrypoint.sh
      - ./auroraboot:/storage
EOF

cd /root
mkdir -p /root/auroraboot
docker compose up -d
while ! echo exit | nc localhost 8081; do sleep 10; done