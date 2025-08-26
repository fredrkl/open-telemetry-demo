#!/bin/bash

# Loki Setup Validation Script
# This script helps validate that Loki is properly configured and running

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${LOKI_NAMESPACE:-"loki"}
TIMEOUT=${TIMEOUT:-"300"}

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

check_namespace() {
    log_info "Checking if namespace '$NAMESPACE' exists..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace '$NAMESPACE' exists"
    else
        log_error "Namespace '$NAMESPACE' does not exist"
        log_info "Create it with: kubectl create namespace $NAMESPACE"
        exit 1
    fi
}

check_pods() {
    log_info "Checking Loki pods status..."
    
    # Get pod information
    if ! kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki &> /dev/null; then
        log_error "No Loki pods found in namespace '$NAMESPACE'"
        log_info "Check if Loki is deployed with: kubectl get applications -n argocd"
        exit 1
    fi
    
    # Check if pods are running
    local running_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki --field-selector=status.phase=Running --no-headers | wc -l)
    local total_pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki --no-headers | wc -l)
    
    if [ "$running_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        log_success "$running_pods/$total_pods Loki pods are running"
    else
        log_warning "$running_pods/$total_pods Loki pods are running"
        log_info "Pod details:"
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki
    fi
}

check_service_account() {
    log_info "Checking Loki service account..."
    
    if kubectl get serviceaccount loki -n "$NAMESPACE" &> /dev/null; then
        log_success "Loki service account exists"
        
        # Check workload identity annotations
        local client_id=$(kubectl get serviceaccount loki -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}')
        if [ -n "$client_id" ]; then
            log_success "Azure Workload Identity client ID configured: $client_id"
        else
            log_warning "Azure Workload Identity client ID not configured"
        fi
    else
        log_error "Loki service account not found"
    fi
}

check_storage_config() {
    log_info "Checking storage configuration..."
    
    # Check if pods have Azure storage configuration
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$pod_name" ]; then
        log_info "Checking storage configuration in pod: $pod_name"
        
        # Check logs for storage-related messages
        if kubectl logs -n "$NAMESPACE" "$pod_name" | grep -q "azure"; then
            log_success "Azure storage configuration detected in logs"
        else
            log_warning "No Azure storage configuration found in logs"
        fi
    fi
}

check_loki_ready() {
    log_info "Checking if Loki is ready..."
    
    # Try to port-forward and check ready endpoint
    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$pod_name" ]; then
        log_info "Testing readiness probe on pod: $pod_name"
        
        # Start port-forward in background
        kubectl port-forward -n "$NAMESPACE" "$pod_name" 3100:3100 &> /dev/null &
        local pf_pid=$!
        
        # Wait a moment for port-forward to establish
        sleep 3
        
        # Test ready endpoint
        if curl -s http://localhost:3100/ready &> /dev/null; then
            log_success "Loki ready endpoint is accessible"
        else
            log_warning "Loki ready endpoint is not accessible"
        fi
        
        # Clean up port-forward
        kill $pf_pid &> /dev/null || true
    fi
}

test_log_ingestion() {
    log_info "Testing log ingestion..."
    
    # Check if test job exists
    if kubectl get job telemetrygen -n otel &> /dev/null; then
        log_info "Test job 'telemetrygen' found"
        
        # Check job status
        local job_status=$(kubectl get job telemetrygen -n otel -o jsonpath='{.status.conditions[0].type}')
        if [ "$job_status" = "Complete" ]; then
            log_success "Test job completed successfully"
        else
            log_warning "Test job status: $job_status"
        fi
    else
        log_info "No test job found. You can create one with: kubectl apply -f setup-test.yaml"
    fi
}

show_useful_commands() {
    log_info "Useful debugging commands:"
    echo ""
    echo "View Loki pods:"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=loki"
    echo ""
    echo "Check pod logs:"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=loki"
    echo ""
    echo "Port-forward to Loki:"
    echo "  kubectl port-forward -n $NAMESPACE svc/loki-gateway 3100:80"
    echo ""
    echo "Test log ingestion:"
    echo "  kubectl apply -f setup-test.yaml"
    echo ""
    echo "Check ArgoCD applications:"
    echo "  kubectl get applications -n argocd"
    echo ""
    echo "View service account details:"
    echo "  kubectl describe serviceaccount loki -n $NAMESPACE"
}

main() {
    echo "================================================"
    echo "          Loki Setup Validation Script"
    echo "================================================"
    echo ""
    
    check_prerequisites
    check_namespace
    check_pods
    check_service_account
    check_storage_config
    check_loki_ready
    test_log_ingestion
    
    echo ""
    echo "================================================"
    echo "             Validation Complete"
    echo "================================================"
    echo ""
    
    show_useful_commands
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --namespace <ns>    Specify Loki namespace (default: loki)"
        echo "  --timeout <sec>     Timeout for operations (default: 300)"
        echo ""
        echo "Environment variables:"
        echo "  LOKI_NAMESPACE      Loki namespace (default: loki)"
        echo "  TIMEOUT             Timeout in seconds (default: 300)"
        exit 0
        ;;
    --namespace)
        NAMESPACE="$2"
        shift 2
        ;;
    --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
    "")
        # No arguments, run main function
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

main "$@"