#!/usr/bin/env bash
# Phase 6.2 — 資源限制與 Overcommit
# 建立指定 CPU/Memory 資源的 VM 並驗證資源分配

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 建立 Resource Demo VM ==="
kubectl apply -f "${REPO_DIR}/manifests/vm-resource-demo.yaml"

echo ""
echo "=== 等待 VM 啟動 ==="
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  vmi/vm-resource-demo --timeout=300s

echo ""
echo "=== 檢查資源分配 ==="
kubectl get vmi vm-resource-demo -o jsonpath='{.spec.domain.resources}' | jq .

echo ""
echo "=== 檢查 virt-launcher Pod 資源 ==="
kubectl top pod -l kubevirt.io/vm=vm-resource-demo 2>/dev/null || echo "需安裝 metrics-server 才能查看資源使用"
