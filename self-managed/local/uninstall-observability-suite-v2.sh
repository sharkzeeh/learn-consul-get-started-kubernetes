#!/usr/bin/bash

NAMESPACE=${1:-monitoring}

echo "Uninstalling observability suite in namespace $NAMESPACE ..."

helm -n $NAMESPACE uninstall grafana
helm -n $NAMESPACE uninstall loki
helm -n $NAMESPACE uninstall prometheus

echo "#######################################" && \
echo "Observability Suite Deletion Complete" && \
echo "#######################################"