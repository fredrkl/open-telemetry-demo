# Open Telemetry Demo

This demo repo showcases how to set up an OpenTelemetry Operator on a
Kubernetes cluster using ArgoCD for deployment management. It uses the
[app-of-apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

The purpose of this demo is to provide a quick way to get started with
OpenTelemetry in a Kubernetes environment.

We use the telemtrygen load generator to send test logs and traces to the open
telemetry collector. I have purposely left out metrics from the OpenTelemetry
Collector configuration. Although the OTel spesification supports metrics, I
reduce the number of moving components to get metrics into Prometheus. The
downside is that the applications have direct integration to Prometheus.

## Loki versions

The first version of Loki is the 1.14.0 where it is installed as a singleBinary
mode.

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
export RESOURCE_GROUP="OTelemetry-demo"
export LOCATION="norwayeast"
export ACCOUNT_NAME="opentelemtrydemostorage"
export ACCOUNT_NAME_TEMPO="opentelemtrytempo"
```

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name opentelemetrydemo \
  --node-count 3 \
  --enable-workload-identity \
  --enable-oidc-issuer \
  --generate-ssh-keys
```

Loki storage account and containers.

```bash
az storage account create \
--name $ACCOUNT_NAME \
--location norwayeast \
--sku Standard_ZRS \
--encryption-services blob \
--resource-group $RESOURCE_GROUP
```

```bash
az storage container create --account-name $ACCOUNT_NAME \
--name chunks && \
az storage container create --account-name $ACCOUNT_NAME \
--name ruler
```

Tempo storage account and containers.

```bash
az storage account create \
--name $ACCOUNT_NAME_TEMPO \
--location norwayeast \
--sku Standard_ZRS \
--encryption-services blob \
--resource-group $RESOURCE_GROUP
```

```bash
az storage container create --account-name $ACCOUNT_NAME_TEMPO \
--name traces
```

```bash
export OIDC=$(az aks show \
--resource-group $RESOURCE_GROUP \
--name opentelemetrydemo \
--query "oidcIssuerProfile.issuerUrl" \
-o tsv)
```

Update the credentials with the OIDC value.

```bash
cat credentials.json | envsubst > credentials-render.json
```

```bash
az identity create \
  --name RESOURCE_GROUP \
  --resource-group $RESOURCE_GROUP
```

```bash
az identity create \
  --name tempo \
  --resource-group $RESOURCE_GROUP
```

```bash
az identity federated-credential create \
  --name LokiFederated \
  --identity-name $RESOURCE_GROUP \
  --resource-group $RESOURCE_GROUP \
  --issuer $OIDC \
  --subject "system:serviceaccount:loki:loki" \
  --audiences "api://AzureADTokenExchange"
```

```bash
az identity federated-credential create \
  --name TempoFederated \
  --identity-name tempo \
  --resource-group $RESOURCE_GROUP \
  --issuer $OIDC \
  --subject "system:serviceaccount:tempo:tempo" \
  --audiences "api://AzureADTokenExchange"
```

```bash
APP_ID=$(az identity show \
  --name $RESOURCE_GROUP \
  --resource-group $RESOURCE_GROUP \
  --query 'clientId' \
  --output tsv)
```

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $APP_ID \
  --scope /subscriptions/d8fc2dcc-fe0e-418a-bf44-7d2512d6d068/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME
```

```bash
APP_ID=$(az identity show \
  --name tempo \
  --resource-group $RESOURCE_GROUP \
  --query 'clientId' \
  --output tsv)
```

```bash
az role assignment create \
  --role "Storage Blob Data Owner" \
  --assignee $APP_ID \
  --scope /subscriptions/d8fc2dcc-fe0e-418a-bf44-7d2512d6d068/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME_TEMPO
```

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $APP_ID \
  --scope /subscriptions/d8fc2dcc-fe0e-418a-bf44-7d2512d6d068/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$ACCOUNT_NAME_TEMPO
```

## Access Grafana

```bash
k port-forward deployments/kube-prometheus-stack-grafana 3000:3000 -n kube-prometheus-stack
```

The default username is `admin` and password is `prom-operator`.

## Add Loki health monitoring dashboard

Add the following dashboard to Grafana:

- <https://grafana.com/grafana/dashboards/11489-loki-canary/>
- <https://grafana.com/grafana/dashboards/14055-loki-stack-monitoring-promtail-loki/>

## Expose OTel Collector

```bash
k port-forward main-collector-{collectorId} 4317:4317 -n otel
```
