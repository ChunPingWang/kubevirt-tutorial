#!/usr/bin/env bash
# Phase 2 — 安裝 CDI（Containerized Data Importer）
# 部署 CDI Operator + CR，用於匯入 VM 磁碟映像到 PVC

set -euo pipefail

echo "=== 取得最新 CDI 版本 ==="
export CDI_VERSION=$(curl -Ls https://github.com/kubevirt/containerized-data-importer/releases/latest \
  | grep -m 1 -o "v[0-9]\.[0-9]*\.[0-9]*")
echo "CDI Version: ${CDI_VERSION}"

echo ""
echo "=== 部署 CDI Operator ==="
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"

echo ""
echo "=== 部署 CDI CR ==="
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"

echo ""
echo "=== 等待 CDI 就緒 ==="
kubectl wait --for=jsonpath='{.status.phase}'=Deployed cdi/cdi -n cdi --timeout=300s

echo ""
echo "=== 確認 CDI 狀態 ==="
kubectl get cdi -n cdi
kubectl get pods -n cdi
