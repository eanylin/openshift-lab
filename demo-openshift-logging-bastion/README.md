# OpenShift logging → bastion syslog (demo)

Reusable assets for the **OpenShift 4.21 / Logging 6.6** demo stack:

- Collect logs with **Red Hat OpenShift Logging** (`ClusterLogForwarder`)
- Forward **application**, **infrastructure**, and **audit** logs to **rsyslog** on a RHEL bastion
- Store logs in-cluster with **LokiStack** + **Console** log viewer (COO UI plugin)
- Enable **user workload monitoring** (Prometheus for user namespaces)
- **Log rotation** on the bastion for small disks

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Cluster access | `oc login` as **cluster-admin** on the bastion (or workstation with kubeconfig) |
| Bastion | RHEL with `rsyslog`, `logrotate`, outbound SSH not required for logging |
| Network | Cluster worker egress → bastion TCP **514** (and optionally **10514**) |
| AWS SG | Open inbound 514/10514 on bastion from cluster egress (80/443 optional) |
| Storage class | Default `gp3-csi` on AWS IPI (override in `config/env.local`) |

## Quick start

### 1. Configure (no secrets in git)

```bash
cd demo-openshift-logging-bastion
cp config/env.example config/env.local
# Edit: BASTION_SYSLOG_HOST, MINIO_ROOT_USER, MINIO_ROOT_PASSWORD
chmod +x scripts/*.sh
```

### 2. Cluster (from bastion after `oc login`)

```bash
./scripts/install.sh
./scripts/verify.sh
```

### 3. Bastion rsyslog receiver

```bash
sudo ./scripts/install-bastion-receiver.sh
./scripts/verify.sh
```

## Repository layout

```text
demo-openshift-logging-bastion/
├── README.md
├── config/
│   └── env.example          # copy → env.local (gitignored)
├── bastion/
│   ├── rsyslog/             # TCP 514 + 10514 → /var/log/openshift-remote.log
│   └── logrotate/           # 50MB rotation + optional hourly cron
├── openshift/
│   ├── 00-namespaces.yaml
│   ├── 01-user-workload-monitoring.yaml
│   ├── 02-logging-operator.yaml
│   ├── 03-loki-operator.yaml
│   ├── 04-coo-operator.yaml
│   ├── 05-minio.yaml        # in-cluster S3 for Loki (demo)
│   ├── 07-lokistack.yaml
│   ├── 09-clusterlogforwarder.yaml.template
│   └── 10-uiplugin.yaml
├── scripts/
│   ├── install.sh
│   ├── install-bastion-receiver.sh
│   ├── enable-audit-forwarding.sh
│   └── verify.sh
└── docs/
    └── SENSITIVE-INFORMATION.md
```

## Viewing logs

### Bastion (`/var/log/openshift-remote.log`)

```bash
# Application logs (example namespace)
sudo grep 'namespace_name=hello-world-app' /var/log/openshift-remote.log | tail -20

# Audit logs
sudo tail -f /var/log/openshift-remote.log | grep --line-buffered 'log_type=audit'

# Disk / rotation
sudo ls -lh /var/log/openshift-remote.log*
sudo logrotate -f /etc/logrotate.d/openshift-remote
df -h /
```

### OpenShift Console

**Observe → Logs** → select namespace (e.g. `hello-world-app`)

Requires LokiStack + UIPlugin (installed by `install.sh`).

### CLI

```bash
oc logs -n hello-world-app -l deployment=hello --tail=50
oc get clusterlogforwarder instance -n openshift-logging
oc get pods -n openshift-logging
```

## User workload monitoring

Enabled via `cluster-monitoring-config` (`enableUserWorkload: true`).

Label demo namespaces:

```bash
oc label namespace hello-world-app openshift.io/cluster-monitoring=true --overwrite
```

Metrics appear in **Observe → Metrics** when the workload exposes `/metrics` and you add a `ServiceMonitor` or `PodMonitor`.

## Security notes

- Syslog uses **plain TCP** (demo only).
- MinIO uses **demo credentials** from `env.local` — change before install.
- Audit logs are **high volume**; rotation is configured but watch disk usage.
- See [docs/SENSITIVE-INFORMATION.md](docs/SENSITIVE-INFORMATION.md) before committing.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| No logs on bastion | SG allows 514 from cluster; `ss -tlnp \| grep 514` on bastion; forwarder Ready |
| `ResolutionFailed` on logging subscription | Subscription `sourceNamespace` must be `openshift-marketplace` |
| Console Logs tab missing | COO CSV Succeeded; `oc get uiplugin logging` Available=True |
| LokiStack not Ready | MinIO pod + bucket; `oc get pods -n openshift-logging` |
| Disk full on bastion | `logrotate -f /etc/logrotate.d/openshift-remote`; reduce `rotate` or `size` |

## Cluster login

On the lab bastion (after SSH):

```bash
export OCP_API="https://api.<cluster>.<domain>:6443"
oc login "$OCP_API" -u kubeadmin -p '<password>'
oc whoami
oc auth can-i '*' '*' --all-namespaces   # expect: yes
```

## Further reading

- [Red Hat OpenShift Logging 6.6 — installing](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.6/html/installing_logging/index)
- [User workload monitoring (OCP 4.21)](https://docs.redhat.com/en/documentation/monitoring_stack_for_red_hat_openshift/4.21/html/configuring_user_workload_monitoring/preparing-to-configure-the-monitoring-stack-uwm)
