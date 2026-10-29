# Tekton pipeline (Act 2+)

Act 3b (reference-aligned) shape:

**clone → test → Sonar → buildah → cosign SPDX → ACS scan → ACS check → CycloneDX → TPA upload → GitOps digest pin (dev) → trigger validate**

Validate PipelineRun (spawned by `trigger-validation`):

**wait-for-attestation (Chains + TAS Rekor) → Conforma `@minimal` → open-prod-promote-mr**

Triggers (optional DX): GitLab webhook → EventListener → Act 3b — see [DEVSPACES.md](DEVSPACES.md).

Act 2 / 3a keep the shorter path: clone → test → buildah → sign-sbom → GitOps → ACS scan.

## Console UI (Pipelines tab)

Two lab Console settings were wrong for this:

1. `ConsolePlugin/pipelines-console-plugin` existed but was **not** listed under `consoles.operator.openshift.io/cluster` `.spec.plugins`
2. Developer perspective was **Disabled** (Pipelines nav is under Developer)

```bash
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}{"\n"}'
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.customization.perspectives}{"\n"}'

# enable plugin + Developer perspective
oc patch consoles.operator.openshift.io cluster --type=merge -p '{
  "spec": {
    "plugins": [
      "advanced-cluster-security",
      "lightspeed-console-plugin",
      "monitoring-plugin",
      "networking-console-plugin",
      "odf-console",
      "monitoring-console-plugin",
      "pipelines-console-plugin",
      "gitops-plugin"
    ],
    "customization": {
      "perspectives": [{"id":"dev","visibility":{"state":"Enabled"}}]
    }
  }
}'
```

Hard-refresh the browser. Switch to **Developer** perspective → project **`fxrate-ci`** → **Pipelines**.

Direct URL:  
https://console-openshift-console.apps.<YOUR_CLUSTER_DOMAIN>/pipelines/ns/fxrate-ci

## Secrets (`setup-secrets.sh`)

```bash
bash cluster/tekton/setup-secrets.sh
```

Creates / refreshes in `fxrate-ci`:

| Secret | Source |
|---|---|
| `gitlab-basic-auth` | GitLab root PAT |
| `quay-push-secret` | Quay `fxrate+builder` robot |
| `acs-api-token` | `ACS_API_TOKEN` env (Central UI) |
| `cosign-signing` | Chains `openshift-pipelines/signing-secrets` |
| `sonarqube-credentials` | `sonarqube/sonarqube-admin` password |
| `tpa-cli-secret` | `trusted-profile-analyzer/oidc-cli` → client `trusted-profile-analyzer-cli` |

Also patches Tekton Chains:

- `transparency.enabled=true` → TAS Rekor (`http://rekor-server.trusted-artifact-signer.svc`)
- `artifacts.pipelinerun.enable-deep-inspection=true`
- Quay push creds mounted into Chains as `DOCKER_CONFIG=/var/chains-docker` (via TektonConfig `chain.options`)

## ACS API token (for `acs-scan` / `acs-check`)

Central: https://central-rhacs-operator.apps.<YOUR_CLUSTER_DOMAIN>

1. Log in (admin password: `oc -n rhacs-operator get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}'`).
2. **Platform Configuration → Integrations → API Token → Generate token**
   - Name: `fxrate-ci-pipeline`
   - Role: **Continuous Integration** (or Analyst)
3. Store only in-cluster (never commit):

```bash
ACS_API_TOKEN='…paste…' bash cluster/tekton/setup-secrets.sh
```

Act 2 / 3b keep `acs-fail-on-policy=false` / `acs-check-fail-on-policy=false` so OS CVEs are recorded, not a hard fail. Act 4 can set check to `true`.

## Apply

```bash
bash cluster/tekton/setup-secrets.sh
oc apply -f cluster/tekton/tasks/
oc apply -f cluster/tekton/pipeline-act2.yaml
oc apply -f cluster/tekton/pipeline-act3a.yaml
oc apply -f cluster/tekton/pipeline-act3b.yaml
oc apply -f cluster/tekton/pipeline-act3b-validate.yaml
oc create -f cluster/tekton/pipelinerun-act3b.yaml
oc -n fxrate-ci get pipelinerun -w
```

TAS (Trusted Artifact Signer) Securesign CR: `cluster/platform/tas/securesign.yaml` (namespace `trusted-artifact-signer`).

## What Act 3b does

| Task | Purpose |
|---|---|
| `clone-source` | GitLab `fxrate/python-cve-upgrade-demo` |
| `test` | Nexus TL hashed install + `pytest` + `pip-audit --local` |
| `sonar-scan` | SonarQube → `fx-rate-service` (gate recorded; task **does not fail** the pipeline). Gate **OK** after S6853 label fix; CSRF hotspots remain To Review. |
| `build-and-push` | RHHI + T2 Containerfile → Quay `fxrate/fx-rate-service:<tag>` |
| `sign-sbom` | syft SPDX → cosign sign + `attest --type spdxjson` |
| `acs-scan` | RHACS inventory / soft scan |
| `acs-check` | `roxctl image check` (soft in Act 3b) |
| `generate-sbom` | CycloneDX 1.6 via syft (for TPA) |
| `upload-sbom-to-tpa` | OIDC client_credentials → TPA `POST /api/v3/sbom` |
| `update-gitops` | Pin `@sha256` on **dev** overlay → push **branch** `main` (webhook SHA is not a branch) |
| `trigger-validation` | Creates `fx-rate-act3b-validate-*` PipelineRun |
| `wait-for-attestation` | Wait for Chains SLSA provenance in Rekor |
| `conforma-validate` | Enterprise Contract `@minimal` against image |
| `open-prod-promote-mr` | After Conforma: open GitLab MR pinning **prod** overlay (ADR-003) |

## Signature / SBOM (where to look)

Not a file in git. After `sign-sbom`, Quay has:

- `sha256-<digest>.sig` — cosign signature
- `sha256-<digest>.att` — SPDX attestation

Chains also writes PipelineRun SLSA provenance to Quay + Rekor when transparency is enabled.

```bash
IMG=quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service@sha256:<digest>
cosign verify --key cluster/policies/cosign.pub --allow-insecure-registry "$IMG"
cosign verify-attestation --key cluster/policies/cosign.pub --allow-insecure-registry --type spdxjson "$IMG"
# Chains / TAS
cosign verify-attestation --key cluster/policies/cosign.pub --rekor-url \
  https://rekor-server-trusted-artifact-signer.apps.<YOUR_CLUSTER_DOMAIN> \
  --type slsaprovenance "$IMG"
```

Gap-fill an already-built digest without rebuilding:

```bash
oc create -f cluster/tekton/taskrun-sign-act3b.yaml
```

## Verified

- PipelineRun `fx-rate-act2-55kfm`: clone → test → buildah → GitOps (pre-ACS task).
- PipelineRun `fx-rate-act2-d4mds`: full path including **acs-scan** —
  `components=102 other_os_vulns=207 pythonish_vulns=6` (pip tooling; app lock still pip-audit clean).
- Act 3a: see [ACT3a.md](ACT3a.md).
- Act 3b: see [ACT3b.md](ACT3b.md) — pipeline `fx-rate-act3b` (+ validate).

## Notes

- Act 1 failure mode can later reuse the same skeleton with `Containerfile.act1-rebuild` (expect red).
- Pipeline `sign-sbom` remains the reliable SPDX path; Chains covers SLSA provenance for Conforma.
- Secrets are namespace-local; not committed to git.
- `update-gitops` re-clones (shared PVC checkouts from `git-clone` are not reliable git dirs for push).
- RHHI bases (`registry.access.redhat.com/hi/python@…`) must be pullable from cluster nodes for Act 3a/3b buildah.
- Act 3b `pytest-pip-audit` uses `LOCKFILE` + `pip-audit --local --vulnerability-service osv` (EgressFirewall blocks PyPI advisories; packages still via Nexus).
- Keycloak client `trusted-profile-analyzer-cli` needs `serviceAccountsEnabled=true` for TPA upload.
