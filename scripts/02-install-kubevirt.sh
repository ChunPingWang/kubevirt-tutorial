#!/usr/bin/env bash
# Phase 1 — 安裝 KubeVirt
# 部署 KubeVirt Operator + CR，並啟用軟體模擬（Kind 環境必要）

set -euo pipefail

echo "=== 取得最新穩定版本號 ==="
export KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo "KubeVirt Version: ${KUBEVIRT_VERSION}"

echo ""
echo "=== 部署 KubeVirt Operator ==="
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"

echo ""
echo "=== 等待 Operator 就緒 ==="
kubectl wait --for=condition=Available deployment/virt-operator \
  -n kubevirt --timeout=300s

echo ""
echo "=== 部署 KubeVirt CR ==="
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

echo ""
echo "=== 等待 KubeVirt 部署完成 ==="
kubectl wait --for=jsonpath='{.status.phase}'=Deployed \
  kubevirt/kubevirt -n kubevirt --timeout=600s

echo ""
echo "=== 啟用軟體模擬 (useEmulation) ==="
kubectl -n kubevirt patch kubevirt kubevirt \
  --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

echo ""
echo "=== 等待重新部署 ==="
kubectl wait --for=jsonpath='{.status.phase}'=Deployed \
  kubevirt/kubevirt -n kubevirt --timeout=300s

echo ""
echo "=== 確認元件狀態 ==="
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt
