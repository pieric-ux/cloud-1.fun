# k8s_apps

Applications of the k3s cluster: the manifests of `40-k8s/` (kustomization,
from infra05 module 05), compared with `kubectl diff` then applied with
`kubectl apply`, from the control plane itself (`k3s kubectl`): no kubectl
nor kubeconfig needed on the controller.

The Postgres Secret is not in the repo: generated from the vault
(`vault_k8s_postgres_password`, `group_vars/k3s/vault.yml`) in a temporary
copy of the manifests, removed after the run. In a diff, kubectl masks the
Secret values.

```bash
make k8s-check                  # kubectl diff, no change
make k8s-apply CONFIRM=yes      # apply when the diff is not empty
```

Never deletes: an object removed from the manifests stays in the cluster
(`kubectl apply` without `--prune`). Checked on 2026-11-04: no difference
with the live cluster.
