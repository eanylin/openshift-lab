# Act 2 — “Just fix the CVEs”

**Spec:** §5.3 · **Talk track:** *To fix a CVE in urllib3, we had to upgrade requests, which needed a new Python…*

## What changes vs Act 0/1

| Layer | Act 0/1 | Act 2 |
|---|---|---|
| Base | `python:3.9-slim` | `python:3.12-slim` (digest) |
| Deps | R0 top-level / L0 historical | `requirements.in` floors + hashed `requirements.txt` (T1) |
| Code | Flask 2 APIs | App factory, no `before_first_request` / `JSONEncoder` |
| Tests | — | `-W error::DeprecationWarning` |

## Reproduce chain traps (AC-2.1 / AC-2.2)

```bash
bash cluster/demo/act2-chain-fails.sh
```

## Deploy path

Preferred: Tekton in `fxrate-ci` (see [TEKTON.md](TEKTON.md)) — clone → pytest/pip-audit → buildah → GitOps digest pin → Argo.

Manual fallback (bastion, `digests.env` populated):

```bash
cd fx-rate-service
podman build -f Containerfile.act2 \
  --build-arg ACT2_BASE="${ACT2_PYTHON_REF}" \
  --build-arg PIP_INDEX_URL="${NEXUS_PYPI_SIMPLE}" \
  -t "${FXRATE_IMAGE_REPO}:2.0.0-act2" .
# push, record digest in digests.env + fx-rate-gitops/base/deployment.yaml, push GitLab
```

## Acceptance

| ID | Notes |
|---|---|
| AC-2.1 / 2.2 | `act2-chain-fails.sh` |
| AC-2.3 | Image build uses hashed install; `pytest` + `pip-audit` in Tekton `test` task |
| AC-2.4 | `/rate/usdsgd` → `{"pair":"usdsgd","rate":"1.2780"}` (Xe mid-market snapshot) |
| AC-2.5 | Tekton `acs-scan` after GitOps deploy. Baseline (`fx-rate-act2-d4mds`): `components=102` · `other_os_vulns=207` (slim OS) · ACS also flags `pip` tooling CVEs (`pythonish_vulns=6`) — app lock still `pip-audit` clean |
