#!/bin/bash
set -e

# -------------------------------
# Variables (Change these)
# -------------------------------
DELEGATE_NAME="bs-docker-delegate"
ACCOUNT_ID="TPsppKhXTR2gI77S6OXXCA"
DELEGATE_TOKEN="NjgxMzU3YTQ5NDE4MGJkYzRkODEwZjA5NTczZTczYjY="
DELEGATE_IMAGE="us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.07.86300"
VM_USER="azureuser"
# -------------------------------

echo "🔹 Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

echo "🔹 Installing Docker..."
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

echo "🔹 Adding user to Docker group..."
sudo usermod -aG docker $VM_USER

echo "⚠️  Please log out and SSH back in for Docker permissions to take effect!"
echo "   After reconnecting, run this script again with '--continue' flag"
sleep 2

if [[ "$1" == "--continue" ]]; then
  echo "🔹 Pulling and running Harness Delegate..."

  # Stop and remove any old container
  if docker ps -a --format '{{.Names}}' | grep -q "$DELEGATE_NAME"; then
    docker stop $DELEGATE_NAME || true
    docker rm $DELEGATE_NAME || true
  fi

  docker run -d --name $DELEGATE_NAME \
    --cpus=1 \
    --memory=2g \
    --restart=always \
    -e DELEGATE_NAME=$DELEGATE_NAME \
    -e NEXT_GEN="true" \
    -e DELEGATE_TYPE="DOCKER" \
    -e ACCOUNT_ID=$ACCOUNT_ID \
    -e DELEGATE_TOKEN=$DELEGATE_TOKEN \
    -e DELEGATE_TAGS="" \
    -e MANAGER_HOST_AND_PORT="https://app.harness.io" \
    -e DELEGATE_AUTOUPGRADE=true \
    $DELEGATE_IMAGE

  echo "✅ Harness Delegate deployed successfully!"
  echo "Check status with: docker ps"
fi
