# KubeVirt on Kind — 初學者實作教學

在 Kubernetes 上跑虛擬機？沒錯，KubeVirt 讓你用 `kubectl` 管理 VM，就像管理 Pod 一樣。

本教學帶你從零開始，在本機用 Kind 建立 K8s 叢集，安裝 KubeVirt 與 CDI，完成虛擬機的建立、啟動、停止、網路連線等完整生命週期操作。

## 這個專案是什麼？

這是一份 **KubeVirt PoC 驗證教學**，適合：

- 想了解 KubeVirt 是什麼的 K8s 使用者
- 需要評估 VM-容器混合部署方案的架構師
- 想在本機快速體驗 KubeVirt 的開發者

## 你會學到什麼

| 主題 | 說明 |
|------|------|
| Kind 叢集建立 | 用 Kind 在本機建立多節點 K8s 叢集 |
| KubeVirt 安裝 | 部署 Operator + CR，理解元件架構 |
| CDI 安裝 | 部署 Containerized Data Importer |
| VM 生命週期 | 建立、啟動、停止、重啟、暫停虛擬機 |
| 磁碟映像匯入 | 用 DataVolume 從 HTTP 匯入 VM 映像 |
| 網路驗證 | VM 與 Pod 互通、透過 Service 暴露 VM |
| 資源管理 | CPU/Memory 配置與 overcommit |

## 前置需求

| 工具 | 最低版本 | 安裝方式 |
|------|---------|---------|
| Docker | 20.10+ | [docs.docker.com](https://docs.docker.com/get-docker/) |
| Kind | v0.20.0+ | `go install sigs.k8s.io/kind@latest` |
| kubectl | 與 K8s 版本 skew ±1 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |

```bash
# 快速確認環境
docker version
kind version
kubectl version --client
```

## 快速開始

### 1. 建立 Kind 叢集

```bash
# 使用專案內的設定檔
kind create cluster --name kubevirt-lab --config kind-kubevirt.yaml

# 確認節點就緒
kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes
```

`kind-kubevirt.yaml` 建立一個 control-plane + 一個 worker 的叢集，並預留 NodePort 30000-30001 給後續測試用。

### 2. 安裝 KubeVirt

```bash
# 取得最新穩定版
export KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo "KubeVirt: ${KUBEVIRT_VERSION}"

# 部署 Operator + CR
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

# 等待部署完成
kubectl wait --for=jsonpath='{.status.phase}'=Deployed kubevirt/kubevirt -n kubevirt --timeout=600s
```

**重要：Kind 環境需要啟用軟體模擬**

Kind 的 Docker container 內沒有 `/dev/kvm` 設備，必須啟用 useEmulation：

```bash
kubectl -n kubevirt patch kubevirt kubevirt \
  --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

> 不啟用的話，VM 會卡在 `Scheduling` 狀態，錯誤訊息為 `Insufficient devices.kubevirt.io/kvm`。

### 3. 安裝 virtctl CLI

`virtctl` 是操作 KubeVirt VM 的專用命令列工具。

```bash
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/')
curl -L -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-${ARCH}"
chmod +x virtctl

# 放到 PATH 中（二擇一）
sudo mv virtctl /usr/local/bin/        # 需要 sudo
# mv virtctl ~/.local/bin/             # 不需要 sudo，確保 ~/.local/bin 在 PATH 中

virtctl version
```

### 4. 安裝 CDI

CDI（Containerized Data Importer）負責將 VM 磁碟映像匯入 Kubernetes PVC。

```bash
export CDI_VERSION=$(curl -Ls https://github.com/kubevirt/containerized-data-importer/releases/latest \
  | grep -m 1 -o "v[0-9]\.[0-9]*\.[0-9]*")

kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"

kubectl wait --for=jsonpath='{.status.phase}'=Deployed cdi/cdi -n cdi --timeout=300s
```

### 5. 建立你的第一個 VM

使用 ContainerDisk（VM 映像包在 container image 裡）是最簡單的方式：

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: testvm
spec:
  runStrategy: Halted
  template:
    metadata:
      labels:
        kubevirt.io/vm: testvm
    spec:
      domain:
        devices:
          disks:
            - name: containerdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        resources:
          requests:
            memory: 128Mi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/kubevirt/cirros-container-disk-demo:latest
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              hostname: testvm
              password: password
              chpasswd:
                expire: false
EOF
```

### 6. 操作 VM

```bash
# 啟動
virtctl start testvm

# 等待 Running
kubectl wait --for=jsonpath='{.status.phase}'=Running vmi/testvm --timeout=300s

# 查看狀態
kubectl get vmi testvm -o wide

# 進入 Console（Ctrl+] 離開）
virtctl console testvm

# 停止
virtctl stop testvm

# 重啟
virtctl restart testvm

# 暫停 / 恢復
virtctl pause vm testvm
virtctl unpause vm testvm
```

## 使用 CDI 匯入磁碟映像

ContainerDisk 簡單但不持久（VM 重啟資料就沒了）。用 DataVolume 可以匯入映像到 PVC，資料會保留。

```bash
# 建立 DataVolume（從 HTTP 下載映像）
cat <<'EOF' | kubectl apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: cirros-dv
spec:
  source:
    http:
      url: "https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img"
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 256Mi
EOF

# 建立使用 DataVolume 的 VM
cat <<'EOF' | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-persistent
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/vm: vm-persistent
    spec:
      domain:
        devices:
          disks:
            - name: datavolumedisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        resources:
          requests:
            memory: 128Mi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: datavolumedisk
          dataVolume:
            name: cirros-dv
EOF
```

> **注意**：Kind 的 StorageClass 使用 `WaitForFirstConsumer` 綁定模式。DataVolume 會在有 Pod（即 VM）引用它時才開始匯入。直接建立 DataVolume 會停在 `WaitForFirstConsumer` 階段，這是正常行為。

## 網路功能

VM 會自動取得 Pod 網段的 IP，可以和其他 Pod 互通：

```bash
# 查看 VM IP
kubectl get vmi testvm -o jsonpath='{.status.interfaces[0].ipAddress}'

# 透過 Service 暴露 VM
virtctl expose vmi testvm --name=testvm-svc --port=22 --type=NodePort
```

## 核心概念速查

| 資源 | 縮寫 | 說明 |
|------|------|------|
| `VirtualMachine` | `vm` | VM 的宣告式定義（類似 Deployment） |
| `VirtualMachineInstance` | `vmi` | VM 的實際運行實例（類似 Pod） |
| `DataVolume` | `dv` | CDI 的磁碟映像匯入宣告 |
| `KubeVirt` | `kv` | KubeVirt 安裝設定 |
| `CDI` | `cdi` | CDI 安裝設定 |

**VM vs VMI 的關係**：`VirtualMachine` 管理 `VirtualMachineInstance` 的生命週期，就像 `Deployment` 管理 `Pod` 一樣。`virtctl start` 一個 VM 時，會自動建立對應的 VMI。

## KubeVirt 元件架構

```
┌─────────────────────────────────────────────┐
│                 API Server                   │
├─────────────────────────────────────────────┤
│  virt-api        接收 API 請求的入口         │
│  virt-controller 管理 VMI 生命週期           │
│  virt-handler    在每個 Node 上管理 VM 進程   │
│  virt-launcher   每個 VM 對應一個 Pod        │
└─────────────────────────────────────────────┘
```

## 常見問題

### VM 卡在 Scheduling 狀態

```
Insufficient devices.kubevirt.io/kvm
```

**原因**：Kind container 內沒有 KVM 設備。
**解法**：啟用 useEmulation（見上方步驟 2）。

### DataVolume 停在 WaitForFirstConsumer

**原因**：Kind 的 StorageClass 使用 `WaitForFirstConsumer` 綁定模式。
**解法**：建立引用該 DataVolume 的 VM，會自動觸發匯入。

### Console 連線無回應

**原因**：VM 還在開機中。
**解法**：等待幾秒後重試。使用軟體模擬時開機較慢。

### spec.running is deprecated 警告

**原因**：新版 KubeVirt 改用 `runStrategy` 取代 `running`。
**解法**：用 `runStrategy: Always`（自動啟動）、`Halted`（不啟動）、`Manual`（手動控制）。

## 清理

```bash
# 刪除所有 VM 和資料
kubectl delete vm --all
kubectl delete dv --all

# 卸載 CDI
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"

# 卸載 KubeVirt
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"

# 銷毀 Kind 叢集
kind delete cluster --name kubevirt-lab
```

## PoC 驗證結果

以下為本教學在實際環境中的驗證結果（2026-02-28）：

| 項目 | 版本 / 結果 |
|------|-----------|
| Kind | v0.24.0 (K8s v1.31.0) |
| KubeVirt | v1.7.1 |
| CDI | v1.64.0 |
| 軟體模擬 (useEmulation) | 必須啟用（Kind 環境） |
| ContainerDisk VM | 建立、啟動、停止、暫停、恢復 |
| DataVolume 匯入 | HTTP 來源匯入成功 |
| 持久化磁碟 VM | 使用 PVC 成功啟動 |
| VM-Pod 網路互通 | ping 成功 (0% packet loss) |
| Service 暴露 VM | NodePort 建立成功，Endpoints 正確 |
| VM Snapshot | Kind 不支援（需 VolumeSnapshot CSI） |
| 資源限制 | CPU/Memory 正確反映在 virt-launcher Pod |

## 專案結構

```
kubevirt-tutorial/
├── README.md                        # 本文件（教學與專案說明）
├── kind-kubevirt.yaml               # Kind 叢集設定檔
└── kubevirt-workshop-checklist.md   # 完整工作清單（含所有測試檢查點）
```

## 參考資源

- [KubeVirt 官方文件](https://kubevirt.io/user-guide/)
- [KubeVirt Quick Start (Kind)](https://kubevirt.io/quickstart_kind/)
- [CDI User Guide](https://kubevirt.io/user-guide/storage/containerized_data_importer/)
- [KubeVirt GitHub](https://github.com/kubevirt/kubevirt)
