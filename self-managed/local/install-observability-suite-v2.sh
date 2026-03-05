#!/usr/bin/bash

NAMESPACE=${1:-monitoring}

echo "Installing observability suite in namespace $NAMESPACE ..."

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
helm repo add grafana https://grafana.github.io/helm-charts && \
helm repo update && \
helm upgrade --install --values helm/prometheus.yaml prometheus prometheus-community/prometheus --version "15.5.3" --namespace "$NAMESPACE" && \
kubectl rollout status deployment prometheus-server --namespace $NAMESPACE --timeout=300s && \
helm upgrade --install loki --values helm/loki.yaml grafana/loki-stack --version "2.9.9" --namespace "$NAMESPACE" && \
kubectl rollout status statefulset loki --namespace $NAMESPACE --timeout=300s && \
helm upgrade --install --values helm/grafana.yaml grafana grafana/grafana --version "6.23.1" --namespace "$NAMESPACE" && \
kubectl rollout status deployment grafana --namespace $NAMESPACE --timeout=300s && \
echo "#######################################" && \
echo "Observability Suite Deployment Complete" && \
echo "#######################################"