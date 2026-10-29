# Cluster bootstrap (P0)

**Stage order after bootstrap:** [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md)  
**Canonical digests:** `fx-rate-service/digests.env.example` + overlay `images:` pins

Lab already has: OpenShift GitOps, Pipelines + Tekton Chains, Quay, GitLab, **RHACS** (Central + SecuredCluster healthy), SonarQube, Trusted Profile Analyzer, **RHTAS** (Securesign Ready).

### New lab / GitHub mirror — parameterize hosts

```bash
cp cluster/lab.env.example cluster/lab.env   # gitignored
# edit APPS_DOMAIN=apps.<YOUR_CLUSTER_DOMAIN>
./cluster/scripts/set-lab-hosts.sh --dry-run
./cluster/scripts/set-lab-hosts.sh
```

One `APPS_DOMAIN` rewrite updates Quay / GitLab / Nexus / SSO / docs / Tekton defaults
(`quay.`, `gitlab-gitlab.`, `nexus.`, `sso.` + apps domain). See `cluster/lab.env.example`.

Then rebuild/push Quay images and pin new RepoDigests — see DEMO-RUNBOOK § Rebuild.

## 1. Namespaces

```bash
chmod +x cluster/bootstrap/bootstrap.sh
./cluster/bootstrap/bootstrap.sh namespaces
./cluster/bootstrap/bootstrap.sh status
```

Creates: `fxrate-ci`, `fxrate-dev`, `fxrate-prod`, `nexus`.

## 2. Nexus Repository CE

P0 Acts 1–2 need a PyPI proxy (`pypi-proxy-pypi`). Act 3b needs a **TL-only** index with **no group** that falls back to PyPI (constitution III). Lab uses Nexus **raw** proxy `raw-proxy-rhtl` as the populate source, then hosted `pypi-hosted-rhtl` as the Act 3b CI/build index (PyPI-format `pypi-proxy-rhtl` cannot map TL’s simple root).

**Lab status:** deployed, CE EULA accepted, `pypi-proxy-pypi` + `raw-proxy-rhtl` + hosted T2 (`populate-hosted-rhtl.sh`).

```bash
oc apply -f cluster/nexus/nexus.yaml
oc adm policy add-scc-to-user anyuid -z nexus -n nexus
bash cluster/nexus/configure-pypi-proxy.sh
```

- Image: `sonatype/nexus3:3.82.0-ubi` pinned by **RepoDigest** in `nexus.yaml` / `digests.env`
- Route: `https://nexus.apps.<YOUR_CLUSTER_DOMAIN>`
- Repos: `pypi-proxy-pypi` → PyPI; `raw-proxy-rhtl` → Trusted Libraries simple root (populate source)
- Act 3b CI index: hosted `pypi-hosted-rhtl` — `bash cluster/nexus/hosted-rhtl/populate-hosted-rhtl.sh` (TL wheel bytes, relative URLs; avoids flaky `packages.redhat.com` from `fxrate-ci`)
- Optional Lightwell **backport** mock (Act 0 pins + `+rhlw-0001`): `bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh` → hosted `pypi-hosted-rhlw` ([LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md))
- **After Nexus PVC/data wipe:** `configure-pypi-proxy.sh` restores proxies only. Re-create hosted repos with both populate scripts above, then regenerate `fx-rate-service/requirements-rhlw.txt` hashes (repack digests change) before the next Lightwell PipelineRun.
- EgressFirewall on `fxrate-ci`: `oc apply -f cluster/network/egressfirewall-fxrate-ci.yaml` (V-08 — see [EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md))

## 3. RHACS (already installed — demo policy tuning)

Current lab: monitoring mode; “Fixable Severity at least Important” exists **without** enforce actions.

For **Act 4** (MR promote + ACS):

1. Keep **inform** on `fxrate-dev`; **Important+ enforce** on `fxrate-prod` (done on this lab).
2. Cosign signature integration + inform policy: `bash cluster/policies/acs-enable-signature-enforce.sh` — flip `ACS_ENFORCE=1` only after Central shows signatures ([EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md)).
3. Prod promote = merge GitLab MR from `open-prod-promote-mr` ([ACT4.md](ACT4.md), ADR-003).
4. Policy IDs: [../policies/ACS-ACT4.md](../policies/ACS-ACT4.md).

Do **not** turn on cluster-wide enforce until the signed Act 3 image exists, or every existing workload will fight you.

## 4. GitOps Applications

Lab GitLab mirror (same tree as local workspace):

- https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo
- Clone URL: `https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo.git`
- Argo path for dev: `fx-rate-gitops/overlays/dev`

```bash
# Repo credential (PAT) — see cluster/gitops/repo-secret.yaml.example
# Lab already has: secret/fxrate-python-cve-upgrade-demo-repo in openshift-gitops

oc apply -f fx-rate-gitops/argocd/fx-rate-dev.yaml
# Prod: auto-sync ON — but digest only changes when a promote MR merges (ADR-003)
oc apply -f fx-rate-gitops/argocd/fx-rate-prod.yaml

# Dev Spaces → GitLab webhook → Tekton (optional but recommended)
bash cluster/tekton/setup-triggers.sh
```

**Lab status:** `fx-rate-dev` / `fx-rate-prod` Synced from GitLab `main`. Prefer Git → Argo over `deploy-act0.sh` (fallback only).

Dev UI: https://fx-rate-service-fxrate-dev.apps.<YOUR_CLUSTER_DOMAIN>/

## 5. Image digests

Recorded in `fx-rate-service/digests.env` (local) and `digests.env.example` (git):

- Legacy Python 3.9-slim + Act 0 image `1.0.0-legacy` (Quay; includes demo UI)
- Act 2 `python:3.12-slim` base + Quay `2.0.0-act2` (see [ACT2.md](ACT2.md))
- RHHI builder/runtime 3.12.14 (for Act 3a)
- Nexus CE 3.82.0-ubi

Still open: Act 5 RHHI digest bump (V-13). Host rewrite: `cluster/scripts/set-lab-hosts.sh`.

## 6. What “done” means for P0 bootstrap

- [x] Namespaces exist  
- [x] Nexus PyPI proxy works (`pypi-proxy-pypi` /simple returns package indexes; CE EULA accepted)  
- [x] Act 0 legacy image in Quay + `fxrate-dev` Deployment + demo UI at `/`  
- [x] Dev Argo app `fx-rate-dev` syncs from GitLab (`fxrate/python-cve-upgrade-demo`)  
- [x] Local workspace ↔ GitLab `main` kept in sync  
- [x] Tekton Act 2 pipeline (test → buildah → GitOps → ACS scan); AC-2.5 slim baseline in [ACT2.md](ACT2.md) / [TEKTON.md](TEKTON.md)  
- [x] Tekton Act 3a RHHI multi-stage; AC-3a baseline in [ACT3a.md](ACT3a.md) (`other_os_vulns=11` vs Act 2 `207`)  
- [x] Tekton Act 3b Trusted Libraries T2; AC-3b in [ACT3b.md](ACT3b.md) (`pypi-hosted-rhtl`)  
- [x] ACS prod enforce + legacy reject; cosign/SBOM ([ACT4.md](ACT4.md) / [ACS-ACT4.md](../policies/ACS-ACT4.md))  
- [x] Pipeline produces signed image + SPDX SBOM via `sign-sbom` task (cosign; Chains key in `cosign-signing`)  
- [x] RHTAS Securesign Ready; Chains transparency → Rekor; Act 3b TPA/Sonar/Conforma ([TEKTON.md](TEKTON.md))  
- [x] EgressFirewall on `fxrate-ci` ([EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md))  
- [x] Dev Spaces + GitLab webhook Triggers ([DEVSPACES.md](DEVSPACES.md))  
- [x] Prod promote via GitLab MR after Conforma ([ARCHITECTURE-DECISIONS.md](ARCHITECTURE-DECISIONS.md) ADR-003)

## 7. ExploitIQ (optional coda)

See [ACT0-EXPLOITIQ.md](ACT0-EXPLOITIQ.md). **Before/after is demo-ready:** Option B → 7 Vulnerable CVEs (urllib3 ×4, jinja2, gunicorn, Flask); Act 3b → Not Vulnerable.

ExploitIQ agent patches (nested-manifest, UV cache, CCA gates) evolve with each release.
Check the ExploitIQ release notes for your version — the workarounds that applied when this
repo was first published may no longer be needed.

