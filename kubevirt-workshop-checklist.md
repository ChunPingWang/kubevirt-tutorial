# KubeVirt on Kind — 完整實作與測試工作清單

> **目標**：在本機使用 Kind 建立 Kubernetes 叢集，安裝 KubeVirt 與 CDI，完成虛擬機生命週期管理的端對端練習。
>
> **適用場景**：企業應用現代化遷移評估、Legacy VM 與容器混合部署 PoC、開發測試環境快速搭建。

---

## Phase 0 — 環境前置準備

### 0.1 確認本機基礎工具

```bash
# 確認 Docker 正常運行
docker version

# 確認 Kind 版本
kind version

# 確認 kubectl 版本
kubectl version --client

# 確認 CPU 虛擬化支援 (Linux)
grep -cE '(vmx|svm)' /proc/cpuinfo
# 輸出 > 0 表示支援硬體虛擬化；若為 0 則後續需啟用軟體模擬
```

**測試檢查點：**
- [ ] Docker daemon 正常運行
- [ ] Kind >= v0.20.0
- [ ] kubectl 版本與目標 K8s 版本相容 (skew ±1)
- [ ] 記錄 CPU 是否支援 KVM（影響後續 useEmulation 設定）

---

### 0.2 建立 Kind 叢集

```bash
# 建立 Kind 叢集設定檔
cat <<EOF > kind-kubevirt.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
    extraPortMappings:
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
      - containerPort: 30001
        hostPort: 30001
        protocol: TCP
EOF

# 建立叢集
kind create cluster --name kubevirt-lab --config kind-kubevirt.yaml

# 確認叢集狀態
kubectl cluster-info --context kind-kubevirt-lab
kubectl get nodes -o wide
```

**測試檢查點：**
- [ ] `kind get clusters` 顯示 `kubevirt-lab`
- [ ] 所有 Node 狀態為 `Ready`
- [ ] `kubectl get pods -A` 所有系統 Pod 為 Running

---

### 0.3 確認 StorageClass

```bash
# Kind 預設內建 local-path-provisioner
kubectl get storageclass
```

預期輸出應包含 `standard` 或 `local-path` 且標記為 `(default)`。CDI 需要預設 StorageClass 才能正常運作。

**測試檢查點：**
- [ ] 存在預設 StorageClass
- [ ] Provisioner 狀態正常

---

## Phase 1 — 安裝 KubeVirt

### 1.1 部署 KubeVirt Operator

```bash
# 取得最新穩定版本號
export KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo "KubeVirt Version: ${KUBEVIRT_VERSION}"

# 部署 Operator
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"

# 等待 Operator 就緒
kubectl wait --for=condition=Available deployment/virt-operator \
  -n kubevirt --timeout=300s
```

**測試檢查點：**
- [ ] `virt-operator` Pod 狀態為 Running
- [ ] Deployment Available 條件為 True

---

### 1.2 部署 KubeVirt Custom Resource

```bash
# 建立 KubeVirt CR
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

# 等待部署完成（Phase = Deployed）
kubectl wait --for=jsonpath='{.status.phase}'=Deployed \
  kubevirt/kubevirt -n kubevirt --timeout=600s

# 確認所有元件狀態
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt
```

**測試檢查點：**
- [ ] KubeVirt CR Phase = `Deployed`
- [ ] `virt-api`、`virt-controller`、`virt-handler` 均為 Running
- [ ] 無 CrashLoopBackOff 或 Error 狀態的 Pod

---

### 1.3 啟用軟體模擬（若無硬體 KVM 支援）

若 Phase 0.1 確認 CPU 不支援 KVM，或在巢狀虛擬化環境中執行：

```bash
kubectl -n kubevirt patch kubevirt kubevirt \
  --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# 等待重新部署
kubectl wait --for=jsonpath='{.status.phase}'=Deployed \
  kubevirt/kubevirt -n kubevirt --timeout=300s
```

**測試檢查點：**
- [ ] Patch 成功無錯誤
- [ ] KubeVirt CR 重新回到 Deployed 狀態

---

### 1.4 安裝 virtctl CLI

```bash
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/')
curl -L -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-${ARCH}"
chmod +x virtctl
sudo mv virtctl /usr/local/bin/

# 驗證安裝
virtctl version
```

**測試檢查點：**
- [ ] `virtctl version` 輸出 Client 與 Server 版本
- [ ] Client 版本與 `KUBEVIRT_VERSION` 一致

---

## Phase 2 — 安裝 CDI（Containerized Data Importer）

### 2.1 部署 CDI Operator 與 CR

```bash
# 取得最新 CDI 版本
export CDI_VERSION=$(curl -Ls https://github.com/kubevirt/containerized-data-importer/releases/latest \
  | grep -m 1 -o "v[0-9]\.[0-9]*\.[0-9]*")
echo "CDI Version: ${CDI_VERSION}"

# 部署 Operator
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"

# 部署 CR
kubectl create -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"

# 等待 CDI 就緒
kubectl wait --for=jsonpath='{.status.phase}'=Deployed cdi/cdi -n cdi --timeout=300s
```

**測試檢查點：**
- [ ] CDI CR Phase = `Deployed`
- [ ] `cdi-operator`、`cdi-apiserver`、`cdi-deployment`、`cdi-uploadproxy` 均為 Running
- [ ] `kubectl get cdi -n cdi` 顯示 Deployed

---

## Phase 3 — 建立第一個虛擬機 (ContainerDisk)

### 3.1 使用 ContainerDisk 快速建立 VM

ContainerDisk 是最簡單的方式，VM 映像檔直接封裝在 Container Image 中，無需額外儲存設定。

```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: testvm-cirros
  labels:
    app: testvm
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/vm: testvm-cirros
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

**測試檢查點：**
- [ ] `kubectl get vm testvm-cirros` 狀態為 Stopped
- [ ] VM 定義無 validation error

---

### 3.2 啟動與操作 VM

```bash
# 啟動 VM
virtctl start testvm-cirros

# 觀察 VMI（VirtualMachineInstance）建立過程
kubectl get vmi -w

# 等待 VMI 進入 Running 狀態
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  vmi/testvm-cirros --timeout=300s
```

**測試檢查點：**
- [ ] VMI Phase = `Running`
- [ ] 對應的 `virt-launcher` Pod 為 Running
- [ ] `kubectl get vmi testvm-cirros -o wide` 顯示 IP 與 Node

---

### 3.3 連線至 VM Console

```bash
# 透過序列 Console 連線（Ctrl+] 離開）
virtctl console testvm-cirros

# 登入後測試（cirros 預設帳號: cirros / 密碼: gocubsgo 或使用 cloud-init 設定的 password）
# 在 VM 內執行：
#   hostname
#   ip addr
#   uname -a
```

**測試檢查點：**
- [ ] 成功進入 VM Console
- [ ] hostname 為 `testvm`（cloud-init 設定）
- [ ] VM 內有網路介面且取得 IP

---

### 3.4 VM 生命週期操作

```bash
# 停止 VM
virtctl stop testvm-cirros
kubectl get vm testvm-cirros
# 預期: Running = false, Status = Stopped

# 重新啟動
virtctl start testvm-cirros
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  vmi/testvm-cirros --timeout=300s

# 重啟（不停止 VM 定義，僅重啟 instance）
virtctl restart testvm-cirros

# 暫停 / 恢復
virtctl pause vm testvm-cirros
kubectl get vmi testvm-cirros -o jsonpath='{.status.conditions}' | jq .
virtctl unpause vm testvm-cirros
```

**測試檢查點：**
- [ ] stop → VM 狀態變為 Stopped，VMI 被刪除
- [ ] start → 新 VMI 被建立並進入 Running
- [ ] restart → VMI 被重建，Pod 更換
- [ ] pause / unpause → 確認 Paused condition 變化

---

## Phase 4 — 使用 CDI 匯入磁碟映像

### 4.1 透過 DataVolume 匯入 Cirros Image

```bash
cat <<EOF | kubectl apply -f -
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

# 觀察匯入進度
kubectl get dv cirros-dv -w

# 等待匯入完成
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  dv/cirros-dv --timeout=600s
```

**測試檢查點：**
- [ ] DataVolume Phase 依序：`ImportScheduled` → `ImportInProgress` → `Succeeded`
- [ ] 對應 PVC 狀態為 Bound
- [ ] Importer Pod 正常完成（Completed）

---

### 4.2 使用匯入的 DataVolume 建立 VM

```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-from-dv
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vm-from-dv
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
      terminationGracePeriodSeconds: 0
      volumes:
        - name: datavolumedisk
          persistentVolumeClaim:
            claimName: cirros-dv
EOF

# 驗證 VM 運行
kubectl get vmi vm-from-dv
virtctl console vm-from-dv
```

**測試檢查點：**
- [ ] VMI 成功進入 Running
- [ ] VM 使用的是 PVC 中的持久化磁碟（非 ContainerDisk）
- [ ] 可透過 Console 登入 VM

---

## Phase 5 — 網路功能驗證

### 5.1 VM 與 Pod 網路互通

```bash
# 取得 VMI 的 Pod IP
VM_IP=$(kubectl get vmi testvm-cirros -o jsonpath='{.status.interfaces[0].ipAddress}')
echo "VM IP: ${VM_IP}"

# 建立一個測試 Pod
kubectl run nettest --image=busybox --restart=Never -- sleep 3600

# 從 Pod ping VM
kubectl exec nettest -- ping -c 3 ${VM_IP}
```

**測試檢查點：**
- [ ] VM 取得 Pod 網段 IP
- [ ] 從 Pod 可成功 ping 到 VM
- [ ] 從 VM Console 內可 ping Pod IP

---

### 5.2 透過 Service 暴露 VM

```bash
# 透過 virtctl 建立 NodePort Service
virtctl expose vmi testvm-cirros --name=testvm-svc --port=22 --type=NodePort

# 或手動建立 Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: testvm-ssh
spec:
  type: NodePort
  selector:
    kubevirt.io/vm: testvm-cirros
  ports:
    - port: 22
      targetPort: 22
      nodePort: 30000
      protocol: TCP
EOF

kubectl get svc testvm-svc
```

**測試檢查點：**
- [ ] Service 建立成功並分配 NodePort
- [ ] `kubectl describe svc testvm-svc` 顯示正確的 Endpoints

---

## Phase 6 — 進階操作

### 6.1 VM Snapshot（快照）

```bash
# 確認 VolumeSnapshot CRD 是否存在
kubectl get crd | grep volumesnapshot

# 若不存在，安裝 snapshot controller（Kind 環境可能需要）
# 參考: https://github.com/kubernetes-csi/external-snapshotter

# 建立快照（需要支援 VolumeSnapshot 的 StorageClass）
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.kubevirt.io/v1beta1
kind: VirtualMachineSnapshot
metadata:
  name: testvm-snap-01
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: vm-from-dv
EOF

kubectl get vmsnapshot
```

> **注意**：Kind 的 local-path-provisioner 不支援 VolumeSnapshot。此步驟用於了解 API 結構，完整測試需在支援快照的儲存環境中執行。

**測試檢查點：**
- [ ] 了解 VirtualMachineSnapshot CRD 結構
- [ ] 在支援環境中 Snapshot Phase = `Succeeded`

---

### 6.2 資源限制與 Overcommit

```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-resource-demo
spec:
  running: true
  template:
    spec:
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        devices:
          disks:
            - name: containerdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        memory:
          guest: 256Mi
        resources:
          requests:
            memory: 256Mi
          limits:
            memory: 512Mi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/kubevirt/cirros-container-disk-demo:latest
EOF

# 檢查資源分配
kubectl get vmi vm-resource-demo -o jsonpath='{.spec.domain.resources}' | jq .
kubectl top pod -l kubevirt.io/vm=vm-resource-demo 2>/dev/null || echo "需安裝 metrics-server"
```

**測試檢查點：**
- [ ] VM 依照指定的 CPU/Memory 規格啟動
- [ ] virt-launcher Pod 的 resource request/limit 反映設定值

---

## Phase 7 — 清理與銷毀

### 7.1 清理所有資源

```bash
# 刪除所有 VM
kubectl delete vm --all

# 等待所有 VMI 終止
kubectl wait --for=delete vmi --all --timeout=120s 2>/dev/null

# 刪除 DataVolume 與 PVC
kubectl delete dv --all
kubectl delete pvc cirros-dv 2>/dev/null

# 刪除測試 Pod 與 Service
kubectl delete pod nettest 2>/dev/null
kubectl delete svc testvm-svc testvm-ssh 2>/dev/null

# 確認清理完成
echo "=== Remaining VMs ===" && kubectl get vm
echo "=== Remaining VMIs ===" && kubectl get vmi
echo "=== Remaining DVs ===" && kubectl get dv
echo "=== Remaining PVCs ===" && kubectl get pvc
```

**測試檢查點：**
- [ ] 無殘留 VM / VMI / DataVolume
- [ ] 無殘留 virt-launcher Pod

---

### 7.2 卸載 KubeVirt 與 CDI

```bash
# 卸載 CDI
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml"
kubectl delete -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"

# 卸載 KubeVirt
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
kubectl delete -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"

# 確認 namespace 已清除
kubectl get ns kubevirt cdi 2>/dev/null
```

---

### 7.3 銷毀 Kind 叢集

```bash
kind delete cluster --name kubevirt-lab

# 驗證叢集已刪除
kind get clusters
```

**測試檢查點：**
- [ ] Kind 叢集已完全刪除
- [ ] Docker 中無殘留的 Kind container

---

## 附錄 A — 常見問題排查

| 症狀 | 可能原因 | 排查指令 |
|------|---------|---------|
| VMI 一直在 `Scheduling` | Node 資源不足或 KVM 不可用 | `kubectl describe vmi <name>` 檢查 Events |
| VMI 進入 `Failed` | useEmulation 未啟用 | 檢查 `virt-launcher` Pod logs |
| DataVolume 停在 `ImportInProgress` | 映像檔 URL 不可達或 StorageClass 問題 | `kubectl logs importer-<dv-name>-*` |
| CDI Phase 不變 | CDI Operator 未就緒 | `kubectl get pods -n cdi` |
| Console 無回應 | VM 尚未完成開機 | 等待後重試，或檢查 `virtctl vnc` |

---

## 附錄 B — 關鍵 CRD 對照表

| CRD | 縮寫 | 用途 |
|-----|------|------|
| `VirtualMachine` | `vm` | VM 定義（宣告式，含期望狀態） |
| `VirtualMachineInstance` | `vmi` | VM 實際運行實例 |
| `VirtualMachineInstanceReplicaSet` | `vmirs` | VM 副本集（類似 ReplicaSet） |
| `DataVolume` | `dv` | CDI 資料匯入宣告 |
| `KubeVirt` | `kv` | KubeVirt 安裝設定 |
| `CDI` | `cdi` | CDI 安裝設定 |

---

## 附錄 C — 企業應用場景參考

針對金融、製造、零售等產業，KubeVirt 的典型應用場景包括：

- **Legacy 應用遷移過渡**：將無法容器化的舊系統（如特定版本的 middleware 或自建交易系統）以 VM 形式納入 K8s 統一管理，逐步完成現代化。
- **開發測試環境**：在同一叢集中混合 VM 與容器，讓開發人員能快速建立接近生產環境的測試拓撲。
- **合規隔離需求**：部分金融法規要求工作負載級別的隔離，VM 提供比容器更強的隔離邊界。
- **混合架構 PoC**：在進行微服務拆分前，以 KubeVirt 驗證新舊系統的整合可行性。

---

> **文件版本**：v1.0 | **最後更新**：2026-02-28
>
> **參考來源**：[KubeVirt 官方文件](https://kubevirt.io/user-guide/) ·
> [KubeVirt Quick Start (Kind)](https://kubevirt.io/quickstart_kind/) ·
> [CDI User Guide](https://kubevirt.io/user-guide/storage/containerized_data_importer/)
