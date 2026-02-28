#!/usr/bin/env bash
# Phase 7 — 清理與銷毀
# 刪除所有 VM、DataVolume、卸載 KubeVirt/CDI、銷毀 Kind 叢集

set -euo pipefail

echo "=== 刪除所有 VM ==="
kubectl delete vm --all
kubectl wait --for=delete vmi --all --timeout=120s 2>/dev/null || true

echo ""
echo "=== 刪除 DataVolume 與 PVC ==="
kubectl delete dv --all
kubectl delete pvc cirros-dv 2>/dev/null || true

echo ""
echo "=== 刪除測試 Pod 與 Service ==="
kubectl delete pod nettest 2>/dev/null || true
kubectl delete svc testvm-svc testvm-ssh 2>/dev/null || true

echo ""
echo "=== 確認清理完成 ==="
echo "--- Remaining VMs ---" && kubectl get vm 2>/dev/null || true
echo "--- Remaining VMIs ---" && kubectl get vmi 2>/dev/null || true
echo "--- Remaining DVs ---" && kubectl get dv 2>/dev/null || true
echo "--- Remaining PVCs ---" && kubectl get pvc 2>/dev/null || true

echo ""
echo "=== 卸載 CDI ==="
export CDI_VERSION=$(curl -Ls https://github.com/kubevirt/containerized-data-importer/releases/latest \
  | grep -m 1 -o "v[0-9]\.[0-9]*\.[0-9]*")
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml" 2>/dev/null || true
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml" 2>/dev/null || true

echo ""
echo "=== 卸載 KubeVirt ==="
export KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml" 2>/dev/null || true
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml" 2>/dev/null || true

echo ""
echo "=== 銷毀 Kind 叢集 ==="
kind delete cluster --name kubevirt-lab

echo ""
echo "=== 驗證叢集已刪除 ==="
kind get clusters
