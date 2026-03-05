# Service Sync

Links:
- https://developer.hashicorp.com/consul/docs/register/service/k8s/service-sync
- https://github.com/hashicorp/consul-k8s/blob/main/charts/consul/values.yaml

The services in Kubernetes and Consul can be automatically synced so that Kubernetes services are available to Consul agents and services in Consul can be available as first-class Kubernetes services.

- enable sync catalog
```yaml
# helm/values-v1-service-sync.yaml
syncCatalog:
  enabled: true
```

- install / upgrade helm chart
```sh
helm upgrade --install --values helm/values-v1-service-sync.yaml consul hashicorp/consul --create-namespace --namespace consul --version "1.9.2"
```

- inspect services in Consul UI
```sh
kubectl port-forward svc/consul-ui --namespace consul 8501:443
```
