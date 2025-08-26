# Open Telemetry Demo

This demo repo showcases how to set up an OpenTelemetry Operator on a
Kubernetes cluster using ArgoCD for deployment management. It uses the
[app-of-apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

## Local K8s cluster

```bash
kind create cluster --config kind-config.yaml --name otel-demo
```

## Setup ArgoCD

We use ArgoCD to manage the cluster. Install it with the following command:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Access the ArgoCD UI with the following command:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Username is `admin` and password is the output from:

```bash
argocd admin initial-password -n argocd
```

## Kick off argoCD sync

```bash
kubectl kustomize kustomize/clusters/overlays/test | k apply -f -
```

You should now see the ArgoCD application in the UI.

## Test the setup

We will be using OpenTelemetry Demo load generator to test the setup.

```bash
kubectl apply -f setup-test.yaml
```

## Loki Setup

This repository includes comprehensive Loki setup for both local development and Azure production environments. Loki is configured to work with OpenTelemetry for log aggregation and analysis.

### Quick Start

For detailed setup instructions, see [loki-setup-guide.md](./loki-setup-guide.md).

#### Local Development (Kind)

```bash
# Create cluster and deploy
kind create cluster --config kind-config.yaml --name otel-demo
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl kustomize kustomize/clusters/overlays/test | kubectl apply -f -

# Validate setup
./scripts/validate-loki.sh
```

#### Azure Production Setup

```bash
# Generate custom configuration
./scripts/generate-loki-config.sh --interactive

# Or with parameters
./scripts/generate-loki-config.sh \
  --storage-account "your-storage" \
  --client-id "your-client-id" \
  --mode distributed

# Run generated setup script
./setup-azure-your-storage.sh
```

### Configuration Files

- **`kustomize/clusters/base/loki.yaml`** - ArgoCD Application for SingleBinary mode (development)
- **`helm-chart-values.yaml`** - Template for Distributed mode (production)
- **`scripts/generate-loki-config.sh`** - Configuration generator with parameterization
- **`scripts/validate-loki.sh`** - Setup validation and troubleshooting

### Deployment Modes

#### SingleBinary Mode (Default)
- **Best for**: Development, testing, demos
- **Resources**: Lower requirements (3 replicas, 1Gi memory each)
- **Features**: Simple setup, all components in one binary

#### Distributed Mode
- **Best for**: Production, high availability
- **Resources**: Higher requirements (multiple components, 2-4Gi memory)
- **Features**: Horizontal scaling, component isolation, high availability

### Azure Requirements

1. **Azure CLI** installed and authenticated
2. **Storage Account** with blob containers: `chunks`, `ruler`, `admin`
3. **Azure AD Application** with federated credentials
4. **AKS Cluster** with workload identity enabled
5. **Storage permissions** for the service principal

### Troubleshooting

Common issues and solutions:

```bash
# Check pod status
kubectl get pods -n loki -l app.kubernetes.io/name=loki

# View logs
kubectl logs -n loki -l app.kubernetes.io/name=loki

# Validate configuration
./scripts/validate-loki.sh

# Test log ingestion
kubectl apply -f setup-test.yaml
```

For detailed troubleshooting, see [loki-setup-guide.md](./loki-setup-guide.md#troubleshooting).

### Security Notes

- **Never commit** actual client IDs or subscription IDs to version control
- Use **Azure Key Vault** for production secrets
- Implement **network policies** to restrict access
- Enable **audit logging** for compliance
- Follow **least privilege** principles for storage permissions

### Monitoring

Monitor these key metrics:
- Pod resource usage and availability
- Log ingestion rates and errors
- Storage account capacity and performance
- Query response times and errors

For complete documentation, see [loki-setup-guide.md](./loki-setup-guide.md).
