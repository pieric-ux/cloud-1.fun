# 40-k8s

Applications of the k3s cluster (from infra05 module 05), applied by the
`k8s_apps` role from the control plane (`make k8s-check`, `make k8s-apply
CONFIRM=yes`). Checked on 2026-11-04: no difference with the live cluster.

| Manifest | Objects |
|---|---|
| `nginx-configmap.yaml`, `nginx-deployment.yaml` | nginx, 3 replicas spread over the nodes, page from a ConfigMap, ClusterIP Service |
| `nginx-ingress.yaml`, `ingress-pieric.yaml` | Traefik ingresses `k3s-control.cloud-1.fun` and `ingress.cloud-1.fun` |
| `netpol-default-deny.yaml`, `netpol-allow-ingress.yaml` | deny all ingress by default; nginx reachable from kube-system (Traefik), Postgres from `app: backend` pods only (enforced by Calico) |
| `postgres-statefulset.yaml` | Postgres 16, headless + ClusterIP Services, 5 GiB volume |

The Postgres Secret is generated from the vault (`vault_k8s_postgres_password`)
at apply time, never written here (`postgres-secret.yaml` is gitignored).

**Postgres data on `local-path`**: the volume is a directory on the node the
pod first ran on (k3s-worker-1), the pod is bound to it. Losing that node
loses the data; it is not in the Proxmox backups as a database dump, only
inside the VM backup of the node.

Not managed: deletion (no `--prune`), the k3s system components (Traefik,
CoreDNS, local-path, Calico: installed by k3s / the k3s-control role).
