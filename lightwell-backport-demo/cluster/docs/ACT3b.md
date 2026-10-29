# Act 3b — Provenance with Trusted Libraries

**Spec:** §5.5 · **Talk track:** *Different hash, same version — rebuilt by Red Hat with provenance. Still not a backport.*

## Lab validation

| ID | Result (2026-10-01) |
|---|---|
| V-01 | All T1 packages present on TL (flask/requests/gunicorn/… wheels) |
| V-03 | Nexus can fetch TL via **raw** proxy `raw-proxy-rhtl` → `packages.redhat.com/trusted-libraries/python/` (PyPI-format `pypi-proxy-rhtl` cannot map TL’s simple root) |
| V-04 | flask 3.1.3 sha256 **differs** PyPI `f4bcbefc…` vs TL `9e5b8ebb…`; requests 2.34.2 similarly |

## Nexus layout note

Trusted Libraries’ simple index **is** `…/trusted-libraries/python/{pkg}/` (no `/simple/` segment). Nexus PyPI proxies always append `/simple/`, so the **populate source** is:

`https://nexus…/repository/raw-proxy-rhtl/`

That raw index emits **absolute** `packages.redhat.com` wheel URLs, which are flaky from `fxrate-ci` (EgressFirewall / CDN). Act 3b CI and `Containerfile.act3b` therefore use a **hosted mirror** of the same TL wheel bytes (relative URLs):

`https://nexus…/repository/pypi-hosted-rhtl/simple`  
Populate once: `bash cluster/nexus/hosted-rhtl/populate-hosted-rhtl.sh`  
(`NEXUS_RHTL_SIMPLE` / `NEXUS_RHTL_RAW` in `digests.env.example`)

## What changes vs Act 3a

| Layer | Act 3a | Act 3b |
|---|---|---|
| Base | RHHI | RHHI (unchanged) |
| Lock | T1 (`requirements.txt`, PyPI hashes) | **T2** (`requirements-t2.txt`, TL hashes) |
| Index | `pypi-proxy-pypi` | **`pypi-hosted-rhtl/simple`** (TL wheels; populate from `raw-proxy-rhtl`) |

## Reproduce AC-3b.1 / AC-3b.3

```bash
bash cluster/demo/act3b-hash-fail.sh   # T1 lock + TL index → hash mismatch
# Missing package (no fallback):
podman run --rm --user 0 --entrypoint /bin/bash "${RHHI_BUILDER_REF}" -lc \
  "pip install --index-url ${NEXUS_RHTL_SIMPLE} not-in-tl-xyz==1.0.0"
```

## Deploy

Full Act 3b path (reference parity): Sonar → build → cosign SPDX → ACS scan/check → CycloneDX → TPA → GitOps → Chains/TAS+Conforma validate. See [TEKTON.md](TEKTON.md).

```bash
bash cluster/tekton/setup-secrets.sh
oc apply -f cluster/tekton/tasks/
oc apply -f cluster/tekton/pipeline-act3b.yaml
oc apply -f cluster/tekton/pipeline-act3b-validate.yaml
oc create -f cluster/tekton/pipelinerun-act3b.yaml
# Watch main + spawned validate run:
oc -n fxrate-ci get pipelinerun -l app.kubernetes.io/part-of=fx-rate-demo -w
```

## Acceptance

| ID | Notes |
|---|---|
| AC-3b.1 | T1 lock vs TL → hash mismatch (blinker Expected≠Got) |
| AC-3b.2 | T2 lock build via Tekton; `pip-audit --local --vulnerability-service osv` (EgressFirewall); wheels from hosted T2 (`pypi-hosted-rhtl`, TL bytes) |
| AC-3b.3 | Unknown package → `No matching distribution` (no PyPI fallback) |

## Verified

**Resting (2026-10-04):**
- **dev+prod** `sha256:6e23506088cc986c047f935e4b84f62880282e593c3aef3d5b9c8462d9a38ea6` — `fx-rate-act3b-push-z57mw` + [MR !3](https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo/-/merge_requests/3) (Sonar label fix)

Prior: `9b44e80e…` via !2; `fbefbfd3…` via !1; `fx-rate-act3b-push-kvktb` / `jb8c2`.

| Item | Prior run (2026-10-01 / gap-fill 2026-10-02) |
|---|---|
| PipelineRun | `fx-rate-act3b-xlzv7` Succeeded (Sonar→…→TPA→GitOps→trigger validate) |
| Image | `…/fx-rate-service@sha256:423ada4652edc90536dcfcd416436a0b07ea4e79953860bc0646ecfcc9bbffe5` |
| TPA SBOM | `POST /api/v3/sbom` → `urn:uuid:01a0fbde-103f-7293-8af1-17f163948a29` |
| Chains/TAS | SLSA provenance on Quay + Rekor; `chains.tekton.dev/signed=true` |
| Validate | `fx-rate-act3b-validate-chk27` Succeeded — wait-attestation + Conforma `@minimal` (33 successes) |
| Earlier | `fx-rate-act3b-rkzwr` — pytest/pip-audit/ACS baselines |
