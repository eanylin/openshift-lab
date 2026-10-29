# Lightwell Backport Demo

Stay on the Python versions a service is already pinned to, and take the fix in place. This OpenShift lab builds that story for an FX-rate service: a Nexus index of `+rhlw-0001` wheels, then the same Trusted Pipeline (signed image, SBOM, Trusted Profile Analyzer, GitOps promote). The upgrade path — interpreter, Trusted Libraries, ACS — sits in the same tree so a backport and an upgrade can be shown side by side.

The Lightwell customer index is represented here by the Nexus mock in [cluster/docs/LIGHTWELL-MOCK.md](cluster/docs/LIGHTWELL-MOCK.md). It uses PEP 440 local versions (`+rhlw-0001`) so pip can install the pins.

ExploitIQ labels in the runbook are what one lab recorded. On a current build, read the model result for each CVE. This repo does not ship agent patches.

| Start here | Why |
|---|---|
| **[cluster/docs/DEMO-RUNBOOK.md](cluster/docs/DEMO-RUNBOOK.md)** | End-to-end stage order, pre-show checks |
| **[cluster/docs/ARCHITECTURE-DECISIONS.md](cluster/docs/ARCHITECTURE-DECISIONS.md)** | Why we chose MR promote, Dev Spaces, egress, etc. |
| [cluster/docs/DEVSPACES.md](cluster/docs/DEVSPACES.md) | Dev Spaces → GitLab webhook → Tekton (no RHDH) |
| [GOALS.md](GOALS.md) | Milestone status |
| [cluster/docs/BOOTSTRAP.md](cluster/docs/BOOTSTRAP.md) | Fresh-lab install |

## Remotes

| Copy | Location |
|---|---|
| This tree | Public GitHub copy. Point it at your lab with `cluster/lab.env.example`. |
| Lab GitLab (authoritative for Argo) | https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo |

**Sync rule:**
- Push `main` → webhook → Act 3b → pins **dev** → Argo auto-syncs `fxrate-dev`
- After Conforma → **promote MR** → merge → Argo auto-syncs `fxrate-prod`

`digests.env` is gitignored; commit pins via `digests.env.example` and overlay `images:` digests.

## What’s in this tree

| Path | Role |
|---|---|
| `fx-rate-service/` | Flask app, Containerfiles, T1/T2 locks, `legacy/` |
| `fx-rate-gitops/` | Kustomize overlays (**separate** dev/prod digests) + Argo CRs |
| `cluster/tekton/` | Pipelines + tasks + **triggers/** (GitLab webhook) |
| `cluster/docs/` | Runbooks + **ARCHITECTURE-DECISIONS** |
| `cluster/exploitiq/` | Scan scripts + OptB Vulnerable seed |
| `devfile.yaml` | OpenShift Dev Spaces |

## Expected resting state (after full setup)

After completing Acts 0–4 on your cluster you should have: Dev Spaces webhook, MR promote path, EgressFirewall, and ExploitIQ coda.

| Piece | State |
|---|---|
| Digests | `fx-rate-service/digests.env.example` + `fx-rate-gitops/overlays/*/kustomization.yaml` |
| Quay | `1.0.0-legacy` · `2.0.0-act2` · `3.0.0-act3a` · `3.0.0-act3b` |
| Dev Spaces | https://devspaces.apps.<YOUR_CLUSTER_DOMAIN> |

| Link | URL |
|---|---|
| **Dev UI** | https://fx-rate-service-fxrate-dev.apps.<YOUR_CLUSTER_DOMAIN>/ |
| **Prod UI** | https://fx-rate-service-fxrate-prod.apps.<YOUR_CLUSTER_DOMAIN>/ |
| Argo | https://openshift-gitops-server-openshift-gitops.apps.<YOUR_CLUSTER_DOMAIN> |
| GitLab | https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo |
| Nexus | https://nexus.apps.<YOUR_CLUSTER_DOMAIN> |

## Promote to prod (FSI/gov)

CI updates **dev** only. Validate opens a **GitLab MR** for **prod**. Merge → Argo syncs `fxrate-prod`. See [ACT4.md](cluster/docs/ACT4.md) and ADR-003.

## Reset / restore

```bash
RESET_CONFIRM=yes make reset           # Act 0 on dev, empty prod
RESET_CONFIRM=yes make restore-act3b   # Act 3b pins on both
```
