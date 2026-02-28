#!/usr/bin/env bash
# Phase 0.1 — 確認本機基礎工具
# 驗證 Docker、Kind、kubectl 是否正確安裝

set -euo pipefail

echo "=== 檢查 Docker ==="
docker version

echo ""
echo "=== 檢查 Kind ==="
kind version

echo ""
echo "=== 檢查 kubectl ==="
kubectl version --client

echo ""
echo "=== 檢查 CPU 虛擬化支援 (Linux) ==="
KVM_COUNT=$(grep -cE '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")
echo "KVM CPU flags: ${KVM_COUNT}"
if [ "$KVM_COUNT" -gt 0 ]; then
  echo "硬體虛擬化支援：是"
else
  echo "硬體虛擬化支援：否（後續需啟用 useEmulation）"
fi
