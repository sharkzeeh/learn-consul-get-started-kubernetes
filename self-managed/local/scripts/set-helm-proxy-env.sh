#!/usr/bin/bash

export NO_PROXY="kubernetes.docker.internal,localhost,127.0.0.1,::1,.cluster.local,.svc"
export no_proxy="$NO_PROXY"

export HTTP_PROXY="socks5://127.0.0.1:1080"
export HTTPS_PROXY="socks5://127.0.0.1:1080"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
