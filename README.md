# Open Telemetry Demo

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
kubectl kustomize kustomize/overlays/test | k apply -f -
```

You should now see the ArgoCD application in the UI.

## Install OpenTelemetry Operator

```bash
kubectl apply -f
