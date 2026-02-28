#!/usr/bin/env bash
# Phase 5 — 網路功能驗證
# 測試 VM 與 Pod 網路互通，並透過 Service 暴露 VM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

VM_NAME="${1:-testvm-cirros}"

echo "=== 取得 VM IP ==="
VM_IP=$(kubectl get vmi "${VM_NAME}" -o jsonpath='{.status.interfaces[0].ipAddress}')
echo "VM IP: ${VM_IP}"

echo ""
echo "=== 建立測試 Pod ==="
kubectl run nettest --image=busybox --restart=Never -- sleep 3600 2>/dev/null || echo "nettest Pod 已存在"
kubectl wait --for=condition=Ready pod/nettest --timeout=60s

echo ""
echo "=== 從 Pod ping VM ==="
kubectl exec nettest -- ping -c 3 "${VM_IP}"

echo ""
echo "=== 透過 Service 暴露 VM ==="
virtctl expose vmi "${VM_NAME}" --name=testvm-svc --port=22 --type=NodePort 2>/dev/null || echo "Service 已存在"
kubectl get svc testvm-svc

echo ""
echo "=== 手動 SSH Service（可選）==="
kubectl apply -f "${REPO_DIR}/manifests/service-vm-ssh.yaml" 2>/dev/null || true
