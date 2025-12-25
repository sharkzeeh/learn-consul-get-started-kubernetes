# Helm proxy settings

If these commands show 403 error
```sh

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

Hang tight while we grab the latest from your chart repositories...
...Unable to get an update from the "hashicorp" chart repository (https://helm.releases.hashicorp.com):
        failed to fetch https://helm.releases.hashicorp.com/index.yaml : 403 Forbidden
```
then set the following variables

## Windows
```ps
$env:NO_PROXY  = "kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
$env:no_proxy  = $env:NO_PROXY

$env:HTTP_PROXY  = "socks5://127.0.0.1:1080"
$env:HTTPS_PROXY = "socks5://127.0.0.1:1080"
$env:http_proxy  = $env:HTTP_PROXY
$env:https_proxy = $env:HTTPS_PROXY
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
