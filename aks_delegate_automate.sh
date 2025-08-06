#!/bin/bash
set -e

# -------------------------------
# Config
# -------------------------------
SUBSCRIPTION_ID="1310e707-0caf-4080-a757-1d7b94c5accb"
LOCATION="eastus2"
OWNER_EMAIL="bhaskar.sharma@neudesic.com"

AKS_RG="tf_aks_harness_rg"
CLUSTER_NAME="tf-aks-harness-cluster"
BASE_NODE_RG="tf_aks_harness_node_rg"
VM_SIZE="Standard_B2s"  # ✅ Cost-optimized

# -------------------------------
# Ensure AKS Resource Group
# -------------------------------
echo "📦 Creating AKS Resource Group..."
az group create \
  --subscription "$SUBSCRIPTION_ID" \
  --name "$AKS_RG" \
  --location "$LOCATION" \
  --tags Owner="$OWNER_EMAIL"

# -------------------------------
# Ensure Default Azure RG for LB
# -------------------------------
echo "📦 Pre-creating DefaultResourceGroup-EUS2 with Owner tag..."
az group create \
  --subscription "$SUBSCRIPTION_ID" \
  --name "DefaultResourceGroup-EUS2" \
  --location "$LOCATION" \
  --tags Owner="$OWNER_EMAIL"

# -------------------------------
# Find or Create Node RG
# -------------------------------
echo "🔍 Checking for existing Node Resource Group..."
NODE_RG=$(az group list --subscription "$SUBSCRIPTION_ID" \
  --query "[?starts_with(name, '$BASE_NODE_RG')].name" -o tsv | head -n 1)

if [ -z "$NODE_RG" ]; then
  UNIQUE_SUFFIX=$(date +%s)
  NODE_RG="${BASE_NODE_RG}_${UNIQUE_SUFFIX}"
  echo "📦 Creating new Node RG: $NODE_RG"
  az group create \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$NODE_RG" \
    --location "$LOCATION" \
    --tags Owner="$OWNER_EMAIL"
else
  echo "✅ Found existing Node RG: $NODE_RG, reusing it."
fi

# -------------------------------
# Create AKS Cluster
# -------------------------------
echo "☸️ Creating AKS Cluster in $LOCATION..."
az aks create \
    --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$AKS_RG" \
    --name "$CLUSTER_NAME" \
    --node-vm-size "$VM_SIZE" \
    --node-count 1 \
    --enable-addons monitoring \
    --generate-ssh-keys \
    --node-resource-group "$NODE_RG" \
    --location "$LOCATION" \
    --tags Owner="$OWNER_EMAIL" \
    --yes

echo "✅ AKS Cluster created successfully!"
