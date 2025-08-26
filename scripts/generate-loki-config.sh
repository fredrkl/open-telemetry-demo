#!/bin/bash

# Loki Configuration Generator
# This script helps generate properly configured Loki YAML files with user-specific values

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Loki Configuration Generator

Usage: $0 [options]

Options:
  --help, -h                  Show this help message
  --storage-account <name>    Azure storage account name
  --client-id <id>           Azure AD application client ID
  --subscription-id <id>     Azure subscription ID
  --resource-group <name>    Azure resource group name
  --mode <mode>              Deployment mode: single or distributed (default: single)
  --output <file>            Output file path (default: loki-generated.yaml)
  --interactive              Interactive mode to prompt for values

Examples:
  $0 --interactive
  $0 --storage-account myaccount --client-id 12345 --mode distributed
  $0 --storage-account myaccount --client-id 12345 --output my-loki.yaml

EOF
}

prompt_for_values() {
    log_info "Interactive configuration mode"
    echo ""
    
    # Storage account
    read -p "Enter Azure storage account name: " STORAGE_ACCOUNT
    if [ -z "$STORAGE_ACCOUNT" ]; then
        log_error "Storage account name is required"
        exit 1
    fi
    
    # Client ID
    read -p "Enter Azure AD application client ID: " CLIENT_ID
    if [ -z "$CLIENT_ID" ]; then
        log_error "Client ID is required"
        exit 1
    fi
    
    # Subscription ID
    read -p "Enter Azure subscription ID: " SUBSCRIPTION_ID
    if [ -z "$SUBSCRIPTION_ID" ]; then
        log_warning "Subscription ID not provided - you'll need to update the setup scripts manually"
    fi
    
    # Resource group
    read -p "Enter Azure resource group name: " RESOURCE_GROUP
    if [ -z "$RESOURCE_GROUP" ]; then
        log_warning "Resource group not provided - using 'otel-demo' as default"
        RESOURCE_GROUP="otel-demo"
    fi
    
    # Deployment mode
    echo ""
    echo "Choose deployment mode:"
    echo "1) SingleBinary (recommended for development/demo)"
    echo "2) Distributed (recommended for production)"
    read -p "Enter choice (1 or 2): " MODE_CHOICE
    
    case $MODE_CHOICE in
        1)
            DEPLOYMENT_MODE="single"
            ;;
        2)
            DEPLOYMENT_MODE="distributed"
            ;;
        *)
            log_warning "Invalid choice, using SingleBinary mode"
            DEPLOYMENT_MODE="single"
            ;;
    esac
    
    # Output file
    read -p "Enter output file path [loki-generated.yaml]: " OUTPUT_FILE
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="loki-generated.yaml"
    fi
}

validate_inputs() {
    if [ -z "$STORAGE_ACCOUNT" ]; then
        log_error "Storage account name is required (use --storage-account or --interactive)"
        exit 1
    fi
    
    if [ -z "$CLIENT_ID" ]; then
        log_error "Client ID is required (use --client-id or --interactive)"
        exit 1
    fi
    
    if [ -z "$DEPLOYMENT_MODE" ]; then
        DEPLOYMENT_MODE="single"
        log_info "Using default deployment mode: single"
    fi
    
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="loki-generated.yaml"
        log_info "Using default output file: $OUTPUT_FILE"
    fi
}

generate_single_binary_config() {
    cat > "$OUTPUT_FILE" << EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-options: "CreateNamespace=true"
    documentation: "Generated configuration for ${STORAGE_ACCOUNT}"
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: loki
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 6.37.0
    helm:
      values: |
        # Generated Loki configuration
        # Storage Account: ${STORAGE_ACCOUNT}
        # Client ID: ${CLIENT_ID}
        # Generated on: $(date)
        
        loki:
          podLabels:
            "azure.workload.identity/use": "true"
          
          schemaConfig:
            configs:
              - from: "2024-04-01"
                store: tsdb
                object_store: azure
                schema: v13
                index:
                  prefix: loki_index_
                  period: 24h
          
          storage_config:
            azure:
              accountName: "${STORAGE_ACCOUNT}"
              container_name: "chunks"
              use_federated_token: true
          
          ingester:
            chunk_encoding: snappy
            chunk_idle_period: 5m
            chunk_target_size: 1048576
            max_chunk_age: 1h
          
          pattern_ingester:
            enabled: true
          
          limits_config:
            allow_structured_metadata: true
            volume_enabled: true
            retention_period: 672h
            ingestion_rate_mb: 10
            ingestion_burst_size_mb: 20
            max_query_parallelism: 32
          
          compactor:
            retention_enabled: true
            delete_request_store: azure
            compaction_interval: 10m
          
          ruler:
            enable_api: true
            storage:
              type: azure
              azure:
                account_name: ${STORAGE_ACCOUNT}
                container_name: ruler
                use_federated_token: true
              alertmanager_url: http://alertmanager:9093
          
          querier:
            max_concurrent: 4
            query_timeout: 300s
          
          storage:
            type: azure
            bucketNames:
              chunks: "chunks"
              ruler: "ruler"
              admin: "admin"
            azure:
              accountName: ${STORAGE_ACCOUNT}
              useFederatedToken: true
        
        serviceAccount:
          name: loki
          annotations:
            "azure.workload.identity/client-id": "${CLIENT_ID}"
          labels:
            "azure.workload.identity/use": "true"
        
        deploymentMode: SingleBinary
        
        gateway:
          enabled: false
        
        minio:
          enabled: false
        
        singleBinary:
          replicas: 3
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi
          persistence:
            enabled: true
            size: 10Gi
        
        chunksCache:
          allocatedMemory: 1000
        
        # Disable distributed components
        backend:
          replicas: 0
        read:
          replicas: 0
        write:
          replicas: 0
        ingester:
          replicas: 0
        querier:
          replicas: 0
        queryFrontend:
          replicas: 0
        queryScheduler:
          replicas: 0
        distributor:
          replicas: 0
        compactor:
          replicas: 0
        indexGateway:
          replicas: 0
        bloomCompactor:
          replicas: 0
        bloomGateway:
          replicas: 0
        
        monitoring:
          serviceMonitor:
            enabled: false
          dashboards:
            enabled: false
        
        test:
          enabled: false
  
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
    automated:
      prune: true
      selfHeal: true
EOF
}

generate_distributed_config() {
    cat > "$OUTPUT_FILE" << EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-options: "CreateNamespace=true"
    documentation: "Generated distributed configuration for ${STORAGE_ACCOUNT}"
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: loki
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 6.37.0
    helm:
      values: |
        # Generated Loki Distributed configuration
        # Storage Account: ${STORAGE_ACCOUNT}
        # Client ID: ${CLIENT_ID}
        # Generated on: $(date)
        
        loki:
          podLabels:
            "azure.workload.identity/use": "true"
          
          schemaConfig:
            configs:
              - from: "2024-04-01"
                store: tsdb
                object_store: azure
                schema: v13
                index:
                  prefix: loki_index_
                  period: 24h
          
          storage_config:
            azure:
              account_name: "${STORAGE_ACCOUNT}"
              container_name: "chunks"
              use_federated_token: true
          
          ingester:
            chunk_encoding: snappy
            chunk_idle_period: 5m
            chunk_target_size: 1048576
            max_chunk_age: 1h
          
          pattern_ingester:
            enabled: true
          
          limits_config:
            allow_structured_metadata: true
            volume_enabled: true
            retention_period: 672h
            ingestion_rate_mb: 50
            ingestion_burst_size_mb: 100
            max_query_parallelism: 64
            max_streams_per_user: 10000
          
          compactor:
            retention_enabled: true
            delete_request_store: azure
            compaction_interval: 10m
          
          ruler:
            enable_api: true
            storage:
              type: azure
              azure:
                account_name: ${STORAGE_ACCOUNT}
                container_name: ruler
                use_federated_token: true
              alertmanager_url: http://alertmanager:9093
          
          querier:
            max_concurrent: 8
            query_timeout: 300s
          
          storage:
            type: azure
            bucketNames:
              chunks: "chunks"
              ruler: "ruler"
              admin: "admin"
            azure:
              accountName: ${STORAGE_ACCOUNT}
              useFederatedToken: true
        
        serviceAccount:
          name: loki
          annotations:
            "azure.workload.identity/client-id": "${CLIENT_ID}"
          labels:
            "azure.workload.identity/use": "true"
        
        deploymentMode: Distributed
        
        # Distributed component configurations
        ingester:
          replicas: 3
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 2000m
              memory: 4Gi
        
        querier:
          replicas: 3
          maxUnavailable: 1
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        queryFrontend:
          replicas: 2
          maxUnavailable: 1
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        
        queryScheduler:
          replicas: 2
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
        
        distributor:
          replicas: 3
          maxUnavailable: 1
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        
        compactor:
          replicas: 1
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 2Gi
        
        indexGateway:
          replicas: 2
          maxUnavailable: 1
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
        
        ruler:
          replicas: 1
          maxUnavailable: 0
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
        
        gateway:
          enabled: true
          replicas: 2
          service:
            type: LoadBalancer
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
        
        minio:
          enabled: false
        
        # Disable SingleBinary components
        singleBinary:
          replicas: 0
        backend:
          replicas: 0
        read:
          replicas: 0
        write:
          replicas: 0
        
        monitoring:
          serviceMonitor:
            enabled: true
          dashboards:
            enabled: true
        
        persistence:
          enabled: true
          size: 100Gi
          storageClass: "premium-ssd"
        
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          runAsGroup: 10001
          fsGroup: 10001
  
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
    automated:
      prune: true
      selfHeal: true
EOF
}

generate_setup_script() {
    local script_name="setup-azure-${STORAGE_ACCOUNT}.sh"
    
    cat > "$script_name" << EOF
#!/bin/bash

# Generated Azure setup script for Loki
# Storage Account: ${STORAGE_ACCOUNT}
# Generated on: $(date)

set -e

# Configuration
export RESOURCE_GROUP="${RESOURCE_GROUP:-otel-demo}"
export LOCATION="\${LOCATION:-norwayeast}"
export ACCOUNT_NAME="${STORAGE_ACCOUNT}"
export CLUSTER_NAME="\${CLUSTER_NAME:-ote-demo}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-your-subscription-id}"

log_info() {
    echo "[INFO] \$1"
}

log_success() {
    echo "[SUCCESS] \$1"
}

log_error() {
    echo "[ERROR] \$1"
    exit 1
}

# Check prerequisites
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed"
fi

# Create resource group
log_info "Creating resource group..."
az group create --name \$RESOURCE_GROUP --location \$LOCATION

# Create AKS cluster
log_info "Creating AKS cluster..."
az aks create \\
  --resource-group \$RESOURCE_GROUP \\
  --name \$CLUSTER_NAME \\
  --node-count 3 \\
  --enable-workload-identity \\
  --enable-oidc-issuer

# Create storage account
log_info "Creating storage account..."
az storage account create \\
  --name \$ACCOUNT_NAME \\
  --location \$LOCATION \\
  --sku Standard_ZRS \\
  --encryption-services blob \\
  --resource-group \$RESOURCE_GROUP

# Create storage containers
log_info "Creating storage containers..."
az storage container create --account-name \$ACCOUNT_NAME --name chunks
az storage container create --account-name \$ACCOUNT_NAME --name ruler
az storage container create --account-name \$ACCOUNT_NAME --name admin

# Get OIDC issuer URL
log_info "Getting OIDC issuer URL..."
export OIDC=\$(az aks show \\
  --resource-group \$RESOURCE_GROUP \\
  --name \$CLUSTER_NAME \\
  --query "oidcIssuerProfile.issuerUrl" \\
  -o tsv)

echo "OIDC Issuer URL: \$OIDC"

# Create Azure AD application
log_info "Creating Azure AD application..."
export APP_ID=\$(az ad app create \\
  --display-name loki \\
  --query appId \\
  -o tsv)

echo "Azure AD App ID: \$APP_ID"

# Generate federated credential
log_info "Creating federated credential..."
cat > credentials-render.json << CRED_EOF
{
    "name": "LokiFederatedIdentity",
    "issuer": "\$OIDC",
    "subject": "system:serviceaccount:loki:loki",
    "description": "Federated identity for Loki accessing Azure resources",
    "audiences": [
      "api://AzureADTokenExchange"
    ]
}
CRED_EOF

az ad app federated-credential create \\
  --id \$APP_ID \\
  --parameters credentials-render.json

# Assign storage permissions
log_info "Assigning storage permissions..."
az role assignment create \\
  --role "Storage Blob Data Contributor" \\
  --assignee \$APP_ID \\
  --scope /subscriptions/\$SUBSCRIPTION_ID/resourceGroups/\$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/\$ACCOUNT_NAME

log_success "Azure setup completed!"
log_info "Next steps:"
log_info "1. Update your Loki configuration with Client ID: \$APP_ID"
log_info "2. Deploy Loki using the generated configuration file"
log_info "3. Run the validation script to verify the setup"
EOF

    chmod +x "$script_name"
    log_success "Generated Azure setup script: $script_name"
}

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --interactive)
            prompt_for_values
            ;;
        *)
            # Parse command line arguments
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --storage-account)
                        STORAGE_ACCOUNT="$2"
                        shift 2
                        ;;
                    --client-id)
                        CLIENT_ID="$2"
                        shift 2
                        ;;
                    --subscription-id)
                        SUBSCRIPTION_ID="$2"
                        shift 2
                        ;;
                    --resource-group)
                        RESOURCE_GROUP="$2"
                        shift 2
                        ;;
                    --mode)
                        DEPLOYMENT_MODE="$2"
                        shift 2
                        ;;
                    --output)
                        OUTPUT_FILE="$2"
                        shift 2
                        ;;
                    *)
                        log_error "Unknown option: $1"
                        ;;
                esac
            done
            ;;
    esac
    
    validate_inputs
    
    log_info "Generating Loki configuration..."
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Client ID: $CLIENT_ID"
    log_info "Deployment Mode: $DEPLOYMENT_MODE"
    log_info "Output File: $OUTPUT_FILE"
    
    case $DEPLOYMENT_MODE in
        single|singlebinary)
            generate_single_binary_config
            ;;
        distributed|dist)
            generate_distributed_config
            ;;
        *)
            log_error "Invalid deployment mode: $DEPLOYMENT_MODE (use 'single' or 'distributed')"
            ;;
    esac
    
    log_success "Generated Loki configuration: $OUTPUT_FILE"
    
    # Generate setup script if we have the required info
    if [ -n "$RESOURCE_GROUP" ] && [ -n "$SUBSCRIPTION_ID" ]; then
        generate_setup_script
    else
        log_info "To generate Azure setup script, provide --resource-group and --subscription-id"
    fi
    
    echo ""
    log_info "Next steps:"
    echo "1. Review and customize the generated configuration"
    echo "2. Apply the configuration: kubectl apply -f $OUTPUT_FILE"
    echo "3. Validate the setup: ./scripts/validate-loki.sh"
}

main "$@"