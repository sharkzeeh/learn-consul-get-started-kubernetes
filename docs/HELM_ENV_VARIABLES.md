# Helm proxy settings

If these commands show 403 error
```sh
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

Hang tight while we grab the latest from your chart repositories...
...Unable to get an update from the "hashicorp" chart repository (https://helm.releases.hashicorp.com):
        failed to fetch https://helm.releases.hashicorp.com/index.yaml : 403 Forbidden
```
or
```sh
helm upgrade --install --values helm/values-v1-service-sync.yaml consul hashicorp/consul --namespace consul --version "1.9.2"
Error: failed to fetch https://helm.releases.hashicorp.com/consul-1.9.2.tgz : 403 Forbidden
```

set the following variables via SOCKS proxy

## Windows
```sh
$env:NO_PROXY  = "kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
$env:no_proxy  = $env:NO_PROXY

$env:HTTP_PROXY  = "socks5://127.0.0.1:1080"
$env:HTTPS_PROXY = "socks5://127.0.0.1:1080"
$env:http_proxy  = $env:HTTP_PROXY
$env:https_proxy = $env:HTTPS_PROXY

$env:ALL_PROXY="socks5://127.0.0.1:1080" # ?
```

or source the variables with a script
```sh
# Dot-source so variables apply to *this* session
. .\scripts\set-helm-proxy-env.ps1

# Optional overrides
# . .\scripts\set-helm-proxy-env.ps1 -Proxy "socks5://127.0.0.1:1080" -NoProxy "kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
```

## Linux
```sh
export NO_PROXY="kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
export no_proxy="$NO_PROXY"

export HTTP_PROXY="socks5://127.0.0.1:1080"
export HTTPS_PROXY="socks5://127.0.0.1:1080"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
```

or source the variable with a script
```sh
source scripts/set-helm-proxy-env.sh
```

## Helm commands

```sh
helm repo list
NAME            URL
hashicorp       https://helm.releases.hashicorp.com

helm search repo hashicorp/consul

helm search repo hashicorp/consul --versions
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
hashicorp/consul        1.9.2           1.22.2          Official HashiCorp Consul Chart
hashicorp/consul        1.9.1           1.22.1          Official HashiCorp Consul Chart
hashicorp/consul        1.9.0           1.22.0          Official HashiCorp Consul Chart
...

helm ls -n consul

# Download helm chart locally
helm pull prometheus-community/prometheus \
  --version 15.18.0 \
  --untardir ./charts/prometheus/15.18.0
```
