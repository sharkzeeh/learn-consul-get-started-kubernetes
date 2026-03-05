param(
  [string]$Proxy = "socks5://127.0.0.1:1080",
  [string]$NoProxy = "kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
)

$env:NO_PROXY = $NoProxy
$env:no_proxy = $NoProxy

$env:HTTP_PROXY = $Proxy
$env:http_proxy = $Proxy

$env:HTTPS_PROXY = $Proxy
$env:https_proxy = $Proxy

$env:ALL_PROXY = $Proxy
$env:all_proxy = $Proxy
