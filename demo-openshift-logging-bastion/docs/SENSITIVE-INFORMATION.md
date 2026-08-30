# Sensitive information audit

This package was prepared for **git check-in**. The following was reviewed.

## Safe to commit (no secrets)

| Path | Notes |
|------|--------|
| `bastion/rsyslog/` | Listener config only |
| `bastion/logrotate/` | Rotation policy |
| `openshift/*.yaml` | Operators, MinIO deployment, LokiStack, UIPlugin — no credentials |
| `openshift/09-clusterlogforwarder.yaml.template` | Uses placeholders `__BASTION_SYSLOG_HOST__` |
| `config/env.example` | Placeholder values only |
| `scripts/*.sh` | Reads secrets from `config/env.local` at runtime |

## Never commit

| Path / item | Why |
|-------------|-----|
| `config/env.local` | Bastion hostname, MinIO passwords |
| `config/secrets.env` | Optional secrets file |
| `openshift/09-clusterlogforwarder.generated.yaml` | Contains real bastion FQDN after install |
| Bastion SSH passwords | Not stored in this repo |
| `kubeadmin` / `oc` tokens | Not stored in this repo |
| MinIO / Loki Kubernetes Secrets | Created by `install.sh` in the cluster only |

## Demo credentials created at install time

`install.sh` creates cluster Secrets from `config/env.local`:

- `minio-credentials` (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`)
- `logging-loki-s3` (same keys + bucket endpoint)

Change defaults in `env.example` before first install. **Do not reuse demo MinIO passwords in production.**

## Network exposure

- Bastion rsyslog listens on TCP **514** and **10514** (plain text, not TLS).
- AWS security group must allow cluster egress to those ports on the bastion.
- Audit forwarding generates **high volume** — logrotate is required on small disks.

## Prior chat exposure

If cluster or bastion passwords were shared in chat or tickets, **rotate them** before a long-lived lab.

## Pre-commit checklist

```bash
# From repo root
grep -rEi 'password|secret_access|apikey|token|CLsY|minioadmin' demo-openshift-logging-bastion/ \
  --exclude-dir=.git || true

# Ensure gitignored files are not staged
git check-ignore -v demo-openshift-logging-bastion/config/env.local
```

Expected: only `env.example` matches generic words like `password` in documentation placeholders.
