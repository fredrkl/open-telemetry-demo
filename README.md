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
kubectl kustomize kustomize/overlays/test | k apply -f -
```

You should now see the ArgoCD application in the UI.

## Test the setup

We will be using OpenTelemetry Demo load generator to test the setup.

```bash
kubectl apply -f setup-test.yaml
```
