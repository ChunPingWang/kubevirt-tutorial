#!/usr/bin/env bash
# Phase 3.2–3.4 — VM 生命週期操作
# 啟動、停止、重啟、暫停、恢復虛擬機

set -euo pipefail

VM_NAME="${1:-testvm-cirros}"

echo "=== 啟動 VM: ${VM_NAME} ==="
virtctl start "${VM_NAME}"

echo ""
echo "=== 等待 VMI 進入 Running ==="
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  "vmi/${VM_NAME}" --timeout=300s

echo ""
echo "=== VMI 狀態 ==="
kubectl get vmi "${VM_NAME}" -o wide

echo ""
echo "提示：執行 'virtctl console ${VM_NAME}' 可進入 VM Console（Ctrl+] 離開）"
echo ""
echo "=== 可用的生命週期操作 ==="
echo "  virtctl stop ${VM_NAME}       # 停止"
echo "  virtctl start ${VM_NAME}      # 啟動"
echo "  virtctl restart ${VM_NAME}    # 重啟"
echo "  virtctl pause vm ${VM_NAME}   # 暫停"
echo "  virtctl unpause vm ${VM_NAME} # 恢復"
