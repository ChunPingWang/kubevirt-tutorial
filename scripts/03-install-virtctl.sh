#!/usr/bin/env bash
# Phase 1.4 — 安裝 virtctl CLI
# 下載並安裝 KubeVirt 的 VM 管理命令列工具

set -euo pipefail

echo "=== 取得 KubeVirt 版本 ==="
export KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo "KubeVirt Version: ${KUBEVIRT_VERSION}"

echo ""
echo "=== 下載 virtctl ==="
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/')
curl -L -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-${ARCH}"
chmod +x virtctl

echo ""
echo "=== 安裝 virtctl ==="
if sudo -n true 2>/dev/null; then
  sudo mv virtctl /usr/local/bin/
else
  echo "無 sudo 權限，安裝到 ~/.local/bin/"
  mkdir -p ~/.local/bin
  mv virtctl ~/.local/bin/
  export PATH="$HOME/.local/bin:$PATH"
fi

echo ""
echo "=== 驗證安裝 ==="
virtctl version
