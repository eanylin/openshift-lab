# Act 3a — Fix the foundation with RHHI

**Spec:** §5.4 · **Talk track:** *Same lockfile, same code — RHHI clears the OS noise and the shell.*

## What changes vs Act 2

| Layer | Act 2 | Act 3a |
|---|---|---|
| Base | `python:3.12-slim` (community) | RHHI `hi/python` builder → distroless runtime |
| Deps / code | T1 lock + app factory | **Unchanged** (constitution VIII) |
| Shell | Present in slim | **None** in runtime (`oc rsh` fails; `oc debug` works) |

## Deploy path

Preferred: Tekton in `fxrate-ci` (see [TEKTON.md](TEKTON.md)) — pipeline `fx-rate-act3a`.

```bash
oc apply -f cluster/tekton/pipeline-act3a.yaml
oc create -f cluster/tekton/pipelinerun-act3a.yaml
oc -n fxrate-ci get pipelinerun -w
```

Manual fallback (bastion, `digests.env` populated):

```bash
cd fx-rate-service
podman build -f Containerfile.act3a \
  --build-arg RHHI_BUILDER="${RHHI_BUILDER_REF}" \
  --build-arg RHHI_RUNTIME="${RHHI_RUNTIME_REF}" \
  --build-arg PIP_INDEX_URL="${NEXUS_PYPI_SIMPLE}" \
  -t "${FXRATE_IMAGE_REPO}:3.0.0-act3a" .
# push, record digest in digests.env + fx-rate-gitops/base/deployment.yaml, push GitLab
```

## Acceptance

| ID | Notes |
|---|---|
| AC-3a.1 | ACS scan after deploy — OS findings **fewer** than Act 2 slim baseline (`other_os_vulns=207`) |
| AC-3a.2 | Same T1 lock; Tekton `test` (`pip-audit`) still 0 |
| AC-3a.3 | `oc rsh` fails (no shell); `oc debug` / ephemeral works |
| AC-3a.4 | Record Act 2 vs Act 3a image sizes |
| AC-3a.5 | Pod on `restricted-v2` random UID serves `/healthz` |

## Verified

- PipelineRun `fx-rate-act3a-9t66c` (2026-10-01): clone → test → buildah → GitOps → acs-scan **Succeeded**
- Digest: `sha256:1a040eeac7a71a5b99e7232a1aaf343a70b449d2b2b01013a50f1b08a6aa3146` on `fxrate-dev` (Synced/Healthy)
- AC-3a.1 ACS inventory: `components=68` · `other_os_vulns=11` (Act 2 slim baseline was **207**) · `pythonish_vulns=8` (pip tooling; app lock still pip-audit clean)
- AC-3a.2 `pytest` + `pip-audit` green on RHHI builder (same T1 lock)
- AC-3a.3 `oc rsh` fails (no shell in runtime)
- AC-3a.4 sizes: Act 2 **147.4 MiB** → Act 3a **125.9 MiB**
- AC-3a.5 `restricted-v2` SCC; namespace UID range `1001130000/10000`; `/healthz` OK; `/rate/usdsgd` → `1.2780`
