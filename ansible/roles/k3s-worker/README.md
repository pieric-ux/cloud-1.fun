k3s-worker
==========

Installs k3s in agent mode and joins the control plane installed by the
`k3s-control` role, then waits until the node is `Ready` (polled from the
control plane, since an agent has no API server).

Requirements
------------

- An inventory group `k3s_control` whose first host runs the k3s server.
- The control plane reachable from the workers on port 6443.
- Calico already applied by `k3s-control`: without a CNI the node stays NotReady.

Role Variables
--------------

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_version` | `""` (required) | k3s release, same as the control plane. |
| `k3s_api_endpoint` | `ansible_host` of `groups['k3s_control'][0]` | Address used in `K3S_URL`. |
| `k3s_install_script` | `/usr/local/bin/k3s-install.sh` | Where get.k3s.io is downloaded. |

The join token is read from `hostvars[groups['k3s_control'][0]].k3s_node_token`
(fact set by `k3s-control`). If the fact is missing (worker playbook run
alone), the token file is read on the control plane.

Dependencies
------------

`k3s-control` must have run first (plays of `30-config.yml`, control plane first).

Example Playbook
----------------

    - hosts: k3s_worker
      roles:
        - k3s-worker

Note
----

The install script runs only once (`creates: /usr/local/bin/k3s`). To reinstall
a node, run `/usr/local/bin/k3s-agent-uninstall.sh` on it first.

License
-------

MIT-0
