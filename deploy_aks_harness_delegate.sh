#!/bin/bash
set -e

# ====== CONFIG ======
RESOURCE_GROUP="aks_harness_rg"
AKS_CLUSTER="HarnessAKSCluster001"
LOCATION="westeurope"
NODE_RG="aks_harness_node_rg_003"
OWNER="bhaskar.sharma@neudesic.com"

NAMESPACE="harness-delegate-ng"
DELEGATE_NAME="bs-aks-helm-delegate"
ACCOUNT_ID="TPsppKhXTR2gI77S6OXXCA"
DELEGATE_TOKEN="NjgxMzU3YTQ5NDE4MGJkYzRkODEwZjA5NTczZTczYjY="
MANAGER_ENDPOINT="https://app.harness.io"
DELEGATE_IMAGE="us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.07.86300"

# ====== 1. Create Resource Group ======
echo "📦 Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# ====== 2. Create AKS Cluster ======
echo "☸️ Creating AKS cluster..."
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --node-count 2 \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --node-resource-group $NODE_RG \
  --tags Owner=$OWNER

# ====== 3. Get AKS Credentials ======
echo "🔑 Getting AKS credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --overwrite-existing

# ====== 4. Add Helm Repo and Update ======
echo "📥 Adding Harness Helm repo..."
helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart
helm repo update

# ====== 5. Create Values.yaml dynamically ======
VALUES_FILE="values.yaml"
cat <<EOF > $VALUES_FILE
delegateName: "$DELEGATE_NAME"
replicas: 2
accountId: "$ACCOUNT_ID"
delegateToken: "$DELEGATE_TOKEN"
managerEndpoint: "$MANAGER_ENDPOINT"
delegateDockerImage: "$DELEGATE_IMAGE"
tags:
  - "aks"
  - "bootcamp"
  - "auto-upgrade"
upgrader:
  enabled: false
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1"
    memory: "2Gi"
logLevel: "INFO"
EOF

# ====== 6. Deploy Harness Delegate ======
echo "🚀 Deploying Harness delegate without upgrader..."
helm upgrade --install $DELEGATE_NAME \
  --namespace $NAMESPACE \
  --create-namespace \
  harness-delegate/harness-delegate-ng \
  -f $VALUES_FILE \
  --set upgrader.enabled=false

# ====== 7. Create Auto-Upgrade CronJob ======
echo "🛠️ Creating auto-upgrade CronJob..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: delegate-auto-upgrade
  namespace: $NAMESPACE
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: default
          containers:
            - name: updater
              image: quay.io/skopeo/stable:latest
              command:
                - /bin/sh
                - -c
                - |
                  echo "🔎 Checking for delegate image updates..."

                  CURRENT_IMAGE=\$(kubectl get deployment $DELEGATE_NAME -n $NAMESPACE \
                    -o jsonpath='{.spec.template.spec.containers[0].image}')
                  echo "Current image: \$CURRENT_IMAGE"

                  LATEST_IMAGE="us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:latest"

                  echo "Fetching latest digest..."
                  LATEST_DIGEST=\$(skopeo inspect docker://\$LATEST_IMAGE | jq -r '.Digest')
                  CURRENT_DIGEST=\$(skopeo inspect docker://\$CURRENT_IMAGE 2>/dev/null | jq -r '.Digest')

                  echo "Current digest: \$CURRENT_DIGEST"
                  echo "Latest digest: \$LATEST_DIGEST"

                  if [ "\$CURRENT_DIGEST" != "\$LATEST_DIGEST" ] && [ -n "\$LATEST_DIGEST" ]; then
                    echo "🚀 New version found. Upgrading delegate..."
                    kubectl set image deployment/$DELEGATE_NAME \
                      harness-delegate=\$LATEST_IMAGE \
                      -n $NAMESPACE
                  else
                    echo "✅ Delegate is already up to date. No upgrade needed."
                  fi
          restartPolicy: OnFailure
EOF

echo "✅ Deployment completed successfully!"
echo "👉 Harness Delegate is running in AKS with daily auto-upgrade enabled."
