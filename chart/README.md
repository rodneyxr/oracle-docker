# Quickstart

Install the chart.

```bash
helm install apex -f values.yaml .
```

Uninstall the chart.

```bash
helm uninstall apex
```

## Prerequisites

- Rook/Ceph cluster

To install Rook/Ceph, run the following commands.

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update
helm install rook-ceph rook-release/rook-ceph --namespace rook-ceph --create-namespace

kubectl apply -f ceph/ceph-cluster.yaml
kubectl apply -f ceph/ceph-fs.yaml
kubectl apply -f ceph/ceph-storageclass.yaml
```
