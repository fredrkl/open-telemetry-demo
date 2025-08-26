# Loki Setup Guide

This guide provides detailed instructions for setting up Grafana Loki with OpenTelemetry in both local and Azure environments.

## Overview

This repository provides two deployment options for Loki:
1. **Local development**: Using Kind cluster with minimal configuration
2. **Production on Azure**: Using AKS with Azure Blob Storage backend

## Configuration Files

- `kustomize/clusters/base/loki.yaml` - ArgoCD Application for Loki deployment
- `helm-chart-values.yaml` - Template values for Helm deployment 
- `credentials.json` - Template for Azure federated identity

## Deployment Modes

### SingleBinary Mode (Current Default)
- **Use case**: Development, testing, small-scale deployments
- **Benefits**: Simple setup, lower resource requirements
- **Limitations**: Single point of failure, limited scalability

### Distributed Mode 
- **Use case**: Production, high-availability, large-scale deployments
- **Benefits**: High availability, horizontal scaling, component isolation
- **Limitations**: More complex setup, higher resource requirements

## Local Development Setup

### Prerequisites
- Docker
- Kind
- kubectl
- ArgoCD CLI (optional)

### Steps

1. Create Kind cluster:
```bash
kind create cluster --config kind-config.yaml --name otel-demo
```

2. Install ArgoCD:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

3. Deploy applications:
```bash
kubectl kustomize kustomize/clusters/overlays/test | kubectl apply -f -
```

4. Verify Loki deployment:
```bash
kubectl get pods -n loki
kubectl logs -n loki -l app.kubernetes.io/name=loki
```

## Azure Production Setup

### Prerequisites
- Azure CLI
- kubectl
- Valid Azure subscription

### Environment Variables
Set these before starting:
```bash
export RESOURCE_GROUP="your-resource-group"
export LOCATION="your-azure-region"  
export ACCOUNT_NAME="your-storage-account"
export CLUSTER_NAME="your-aks-cluster"
export SUBSCRIPTION_ID="your-subscription-id"
```

### Steps

1. Create Azure resources:
```bash
# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster with workload identity
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --node-count 3 \
  --enable-workload-identity \
  --enable-oidc-issuer

# Create storage account
az storage account create \
  --name $ACCOUNT_NAME \
  --location $LOCATION \
  --sku Standard_ZRS \
  --encryption-services blob \
  --resource-group $RESOURCE_GROUP

# Create storage containers
az storage container create --account-name $ACCOUNT_NAME --name chunks
az storage container create --account-name $ACCOUNT_NAME --name ruler  
az storage container create --account-name $ACCOUNT_NAME --name admin
```

2. Configure workload identity:
```bash
# Get OIDC issuer URL
export OIDC=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" \
  -o tsv)

# Create Azure AD application
export APP_ID=$(az ad app create \
  --display-name loki \
  --query appId \
  -o tsv)

# Create federated credential
cat credentials.json | envsubst > credentials-render.json
az ad app federated-credential create \
  --id $APP_ID \
  --parameters credentials-render.json

# Assign storage permissions
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $APP_ID \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME
```

3. Update Loki configuration:
   - Update the client ID in `kustomize/clusters/base/loki.yaml`
   - Update storage account name and container names
   - Deploy via ArgoCD

### Troubleshooting

#### Common Issues

**Loki pods failing to start:**
```bash
# Check pod status
kubectl get pods -n loki

# Check pod logs
kubectl logs -n loki <pod-name>

# Check workload identity configuration
kubectl describe serviceaccount -n loki loki
```

**Storage access issues:**
```bash
# Verify storage account permissions
az role assignment list --assignee $APP_ID --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME

# Test storage connectivity
kubectl run -it --rm debug --image=mcr.microsoft.com/azure-cli --restart=Never -- /bin/bash
```

**ArgoCD sync issues:**
```bash
# Check application status
kubectl get applications -n argocd

# View sync details
argocd app get loki --refresh
```

#### Validation Steps

1. **Verify Loki is running:**
```bash
kubectl get pods -n loki -l app.kubernetes.io/name=loki
```

2. **Check storage configuration:**
```bash
kubectl logs -n loki -l app.kubernetes.io/name=loki | grep -i storage
```

3. **Test log ingestion:**
```bash
kubectl apply -f setup-test.yaml
kubectl logs -n otel job/telemetrygen
```

4. **Query Loki (if gateway is exposed):**
```bash
kubectl port-forward -n loki svc/loki-gateway 3100:80
curl http://localhost:3100/ready
```

## Security Best Practices

1. **Use Azure Key Vault** for sensitive configuration
2. **Implement network policies** to restrict pod communication  
3. **Enable audit logging** for Loki access
4. **Rotate credentials** regularly
5. **Use least privilege** for storage account permissions

## Resource Requirements

### Minimum (Development)
- CPU: 500m per replica
- Memory: 1Gi per replica
- Storage: 10Gi persistent volume

### Recommended (Production)
- CPU: 1000m per replica
- Memory: 2Gi per replica  
- Storage: 100Gi+ persistent volume

## Monitoring and Alerting

Monitor these key metrics:
- `loki_ingester_memory_streams` - Number of active streams
- `loki_distributor_ingester_append_failures_total` - Failed append operations
- `loki_chunk_store_index_lookups_per_query` - Query performance
- Storage account metrics for capacity and throughput

## Further Reading

- [Loki Documentation](https://grafana.com/docs/loki/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [ArgoCD Application Patterns](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)