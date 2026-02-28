#!/usr/bin/env bash
# Phase 4.1 — 透過 DataVolume 匯入磁碟映像
# 從 HTTP 下載 Cirros 映像並匯入到 PVC

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 建立 DataVolume ==="
kubectl apply -f "${REPO_DIR}/manifests/datavolume-cirros.yaml"

echo ""
echo "=== 觀察匯入進度（Ctrl+C 停止觀察）==="
echo "DataVolume 會在有 VM 引用時才開始匯入（WaitForFirstConsumer）"
kubectl get dv cirros-dv
