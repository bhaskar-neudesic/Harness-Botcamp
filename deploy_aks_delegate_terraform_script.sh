#!/bin/bash
set -e

### ====== CONFIGURATION ======
RESOURCE_GROUP="tf_aks_harness_rg"
AKS_CLUSTER="HarnessAKSCluster001"
LOCATION="westeurope"
NODE_RG="tf_aks_harness_node_rg_001"
OWNER="bhaskar.sharma@neudesic.com"

NAMESPACE="harness-delegate-ng"
DELEGATE_NAME="bs-aks-helm-delegate"
ACCOUNT_ID="TPsppKhXTR2gI77S6OXXCA"
DELEGATE_TOKEN="NjgxMzU3YTQ5NDE4MGJkYzRkODEwZjA5NTczZTczYjY="
MANAGER_ENDPOINT="https://app.harness.io"
DELEGATE_IMAGE="us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.07.86300"

# ====== 1. Create Resource Group ======
echo "📦 Creating resource group with Owner tag..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --tags Owner=$OWNER

# ====== 2. Create Node Resource Group (manually to tag early) ======
echo "📦 Creating node resource group with Owner tag..."
az group create \
  --name $NODE_RG \
  --location $LOCATION \
  --tags Owner=$OWNER

# ====== 3. Create AKS Cluster ======
echo "☸️ Creating AKS cluster..."
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --node-count 2 \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --node-resource-group $NODE_RG \
  --tags Owner=$OWNER

echo "🔑 Getting AKS credentials..."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --overwrite-existing

# ====== 4. Tag Node Resource Group again (safety check) ======
echo "🏷️ Ensuring Node Resource Group is tagged..."
az group update \
  --name $NODE_RG \
  --set tags.Owner=$OWNER

# ====== 5. Harness Delegate Deployment ======
echo "📥 Adding Harness Helm repo..."
helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart
helm repo update

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

echo "🚀 Deploying Harness delegate..."
helm upgrade --install $DELEGATE_NAME \
  --namespace $NAMESPACE \
  --create-namespace \
  harness-delegate/harness-delegate-ng \
  -f $VALUES_FILE \
  --set upgrader.enabled=false

# ====== 6. Auto-Upgrade CronJob ======
echo "🛠️ Setting up auto-upgrade CronJob..."
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
          containers:
            - name: updater
              image: quay.io/skopeo/stable:latest
              command:
                - /bin/sh
                - -c
                - |
                  CURRENT_IMAGE=\$(kubectl get deployment $DELEGATE_NAME -n $NAMESPACE \
                    -o jsonpath='{.spec.template.spec.containers[0].image}')
                  LATEST_IMAGE="us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:latest"
                  LATEST_DIGEST=\$(skopeo inspect docker://\$LATEST_IMAGE | jq -r '.Digest')
                  CURRENT_DIGEST=\$(skopeo inspect docker://\$CURRENT_IMAGE 2>/dev/null | jq -r '.Digest')

                  if [ "\$CURRENT_DIGEST" != "\$LATEST_DIGEST" ] && [ -n "\$LATEST_DIGEST" ]; then
                    kubectl set image deployment/$DELEGATE_NAME \
                      harness-delegate=\$LATEST_IMAGE \
                      -n $NAMESPACE
                  else
                    echo "Delegate is already up to date."
                  fi
          restartPolicy: OnFailure
EOF

# ====== 7. Install Terraform ======
echo "🌍 Installing Terraform..."
sudo apt-get update && sudo apt-get install -y wget unzip jq
wget https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
unzip terraform_1.9.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version

# ====== 8. Sample Terraform Project ======
echo "📂 Setting up sample Terraform infra project..."
mkdir -p terraform-infra
cat <<EOF > terraform-infra/main.tf
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "bootcamp-tf-rg"
  location = "westeurope"
  tags = {
    Owner = "$OWNER"
  }
}

resource "azurerm_app_service_plan" "asp" {
  name                = "bootcamp-asp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    tier = "Basic"
    size = "B1"
  }
  tags = {
    Owner = "$OWNER"
  }
}

resource "azurerm_app_service" "webapp" {
  name                = "bootcamp-webapp-\${random_integer.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.asp.id
  tags = {
    Owner = "$OWNER"
  }
}

resource "random_integer" "rand" {
  min = 1000
  max = 9999
}
EOF

cat <<EOF > terraform-infra/variables.tf
variable "location" {
  default = "westeurope"
}
EOF

terraform -chdir=terraform-infra init

# ====== 9. Azure DevOps Pipeline YAML ======
echo "📜 Creating Azure DevOps pipeline file..."
mkdir -p azure-pipelines
cat <<EOF > azure-pipelines/terraform-pipeline.yml
trigger:
- main

pool:
  vmImage: ubuntu-latest

steps:
- task: TerraformInstaller@1
  inputs:
    terraformVersion: '1.9.5'

- task: TerraformTaskV4@4
  inputs:
    provider: 'azurerm'
    command: 'init'
    workingDirectory: 'terraform-infra'

- task: TerraformTaskV4@4
  inputs:
    provider: 'azurerm'
    command: 'apply'
    workingDirectory: 'terraform-infra'
    environmentServiceNameAzureRM: '<YOUR-SERVICE-CONNECTION>'
    args: '-auto-approve'
EOF

echo "✅ Bootcamp setup complete!"
echo "👉 AKS + Delegate + Auto-Upgrade + Terraform pipeline created (with Owner tag)."
