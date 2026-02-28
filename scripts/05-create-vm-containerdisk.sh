#!/usr/bin/env bash
# Phase 3.1 — 建立 ContainerDisk VM
# 使用 ContainerDisk 方式建立 Cirros 虛擬機

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 建立 ContainerDisk VM ==="
kubectl apply -f "${REPO_DIR}/manifests/vm-containerdisk.yaml"

echo ""
echo "=== 確認 VM 狀態 ==="
kubectl get vm testvm-cirros
