#!/usr/bin/env bash
# Phase 4.2 — 使用 DataVolume 建立持久化 VM
# 建立使用 PVC 持久化磁碟的虛擬機

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 建立使用 DataVolume 的 VM ==="
kubectl apply -f "${REPO_DIR}/manifests/vm-datavolume.yaml"

echo ""
echo "=== 等待 VM 啟動 ==="
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  vmi/vm-from-dv --timeout=600s 2>/dev/null || echo "VM 啟動中（DataVolume 匯入可能需要時間）..."

echo ""
echo "=== VM 狀態 ==="
kubectl get vm vm-from-dv
kubectl get vmi vm-from-dv 2>/dev/null || true
kubectl get dv cirros-dv
