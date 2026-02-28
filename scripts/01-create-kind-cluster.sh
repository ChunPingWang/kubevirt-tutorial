#!/usr/bin/env bash
# Phase 0.2 — 建立 Kind 叢集
# 建立含 control-plane + worker 的 Kind 叢集，預留 NodePort 30000-30001

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 建立 Kind 叢集 ==="
kind create cluster --name kubevirt-lab --config "${REPO_DIR}/kind-kubevirt.yaml"

echo ""
echo "=== 確認叢集狀態 ==="
kubectl cluster-info --context kind-kubevirt-lab
kubectl get nodes -o wide

echo ""
echo "=== 確認 StorageClass ==="
kubectl get storageclass
