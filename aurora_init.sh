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
    [p2p_network_token]=$(docker run -ti --rm quay.io/mudler/edgevpn -b -g)
    [infisical_environment]=$INFISICAL_ENVIRONMENT
    [infisical_id]=$INFISICAL_ID
    [infisical_secret]=$INFISICAL_SECRET
    [infisical_project]=$INFISICAL_PROJECT
    [infisical_token]=$INFISICAL_TOKEN
    [cluster_domain]=$CLUSTER_DOMAIN
)

#base64 encode needed
variables[infisical_environment]=\$(echo -n \${variables[infisical_environment]} | base64 -w0)
variables[infisical_id]=\$(echo -n \${variables[infisical_id]} | base64 -w0)
variables[infisical_secret]=\$(echo -n \${variables[infisical_secret]} | base64 -w0)
variables[infisical_project]=\$(echo -n \${variables[infisical_project]} | base64 -w0)
variables[infisical_token]=\$(echo -n \${variables[infisical_token]} | base64 -w0)
variables[cluster_domain]=\$(echo -n \${variables[cluster_domain]} | base64 -w0)

curl -o /tmp/pulled-cloud-config.yaml https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/cloud-config.yaml
sed_command="sed"

# Dynamically build the sed command based on the variables
for key in "\${!variables[@]}"; do
    value=\${variables[\$key]}
    # Escape slashes in the value
    escaped_value=$(echo \$value | sed 's/\//\\\//g')
    sed_command+=" -e 's/{{ \${key^^} }}/\${escaped_value}/g'"
done

# Apply the transformations
sed_command+=" /tmp/pulled-cloud-config.yaml > /tmp/cloud-config.yaml"
eval \$sed_command

/usr/bin/auroraboot --cloud-config /tmp/cloud-config.yaml https://raw.githubusercontent.com/6ixfalls/homelab-gitops/main/bootstrap/auroraboot-config.yaml
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