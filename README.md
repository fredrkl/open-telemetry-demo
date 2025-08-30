# Open Telemetry Demo

This demo repo showcases how to set up an OpenTelemetry Operator on a
Kubernetes cluster using ArgoCD for deployment management. It uses the
[app-of-apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

The purpose of this demo is to provide a quick way to get started with
OpenTelemetry in a Kubernetes environment.

We use the telemtrygen load generator to send test logs and traces to the open
telemetry collector. The collector forwards logs to Loki and traces to Tempo for
distributed tracing analysis. I have purposely left out metrics from the OpenTelemetry
Collector configuration. Although the OTel spesification supports metrics, I
reduce the number of moving components to get metrics into Prometheus. The
downside is that the applications have direct integration to Prometheus.

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

## Loki setup demo

In order to setup Loki, we will be using an Azure Kubernetes Service (AKS)
cluster. You can follow the instructions above to get the open-telemetry
operator up and running on AKS as well. Once that is done, continue here. This
guide is following:
<https://grafana.com/docs/loki/latest/setup/install/helm/deployment-guides/azure/>.

### AKS

```bash
export RESOURCE_GROUP="otel-demo"
export LOCATION="norwayeast"
export ACCOUNT_NAME="oteldemo"
```

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name ote-demo \
  --node-count 3 \
  --enable-workload-identity \
  --enable-oidc-issuer
```

```bash
az storage account create \
--name oteldemo \
--location norwayeast \
--sku Standard_ZRS \
--encryption-services blob \
--resource-group  otel-demo
```

```bash
az storage container create --account-name $ACCOUNT_NAME \
--name chunk && \
az storage container create --account-name $ACCOUNT_NAME \
--name ruler && \
az storage container create --account-name $ACCOUNT_NAME \
--name admin
```

```bash
export OIDC=$(az aks show \
--resource-group $RESOURCE_GROUP \
--name ote-demo \
--query "oidcIssuerProfile.issuerUrl" \
-o tsv)
```

Update the credentials with the OIDC value.

```bash
cat credentials.json | envsubst > credentials-render.json
```

```bash
export APP_ID=$(az ad app create \
 --display-name loki \
 --query appId \
 -o tsv)
 ```

```bash
 az ad app federated-credential create \
  --id $APP_ID \
  --parameters credentials-render.json
```

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $APP_ID \
  --scope /subscriptions/d8fc2dcc-fe0e-418a-bf44-7d2512d6d068/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME
```
