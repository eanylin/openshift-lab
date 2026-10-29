# Lightwell Network mock (lab only)

**Not product content.** This lab cannot reach `packages.redhat.com/lightwell/...`, so we mock the **customer-visible versioning** on Nexus for demos.

## Thesis: backport in place, not upgrade

| Story | Version shape | What it proves |
|---|---|---|
| Act 0 | `flask==2.2.2` | Inherited vulnerable pins |
| Act 3b (TL) | `flask==3.1.3` (T2) | **Upgrade** via Trusted Libraries |
| Lightwell mock | `urllib3==1.26.14+rhlw-0001` | **Backport / remediate in place** -- same upstream version + build suffix |

Lightwell's point is that you stay on the version you are stuck on and take remediations. Mocking `3.1.3+rhlw....` would look like an upgrade and defeats that story.

## Naming: docs vs pip

| Source | Example |
|---|---|
| Lightwell docs (display) | `urllib3` @ `1.26.14.rhlw-00001` |
| This lab mock (PEP 440) | `urllib3==1.26.14+rhlw-0001` |

Product docs append `.rhlw-0000X` to the upstream version ([version suffixes](https://docs.redhat.com/en/documentation/lightwell_network/current/get_started-patched_artifact_versions)). That dotted form is **not valid PEP 440**, so stock `pip` rejects `urllib3==1.26.14.rhlw-00001`.

The lab mock uses the **PEP 440 local-version** form that pip accepts: `2.2.2+rhlw-0001`. Same story for customers: same project name, **same upstream version** + Lightwell build id. On stage, say the product suffix is `.rhlw-...` and show `pip show` / SBOM with `+rhlw-...` as the lab-installable equivalent.

| Piece | Lab value |
|---|---|
| Nexus repo | **hosted** PyPI `pypi-hosted-rhlw` |
| Simple index | `https://nexus.../repository/pypi-hosted-rhlw/simple/` |
| Example pin | `urllib3==1.26.14+rhlw-0001` |
| Env | `NEXUS_RHLW_SIMPLE` in `digests.env.example` |
| Requirements | `fx-rate-service/requirements-rhlw.txt` (hashed Act 0 set; markupsafe 2.1.5 for binary wheels) |
| Containerfile | `fx-rate-service/Containerfile.rhlw` |
| Pipeline | `fx-rate-lightwell` (full E2E: GitOps + Conforma + promote MR) |

Act 3b resting path uses hosted T2 (`pypi-hosted-rhtl` -- TL wheel bytes at newer versions). Lightwell mock is a **parallel** index that keeps **Act 0 upstream versions** on the **same RHHI base**. Every package flagged **Vulnerable** by ExploitIQ (urllib3, jinja2, flask, gunicorn) plus requests (defensive) is backported with `+rhlw-0001` — 7 of 7 Vulnerable CVEs covered. The other 8 packages stay at their original upstream versions.

## Populate Nexus

```bash
bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh
```

Downloads Act 0 wheels from `pypi-proxy-pypi`, repacks to `+rhlw-0001`, purges prior components in `pypi-hosted-rhlw`, then uploads.

**Hosted repo is ephemeral with Nexus data.** If `pypi-hosted-rhlw` (or `pypi-hosted-rhtl`) disappears after a cluster/Nexus wipe, re-run the populate script(s). Repacked wheels get **new digests** -- regenerate `fx-rate-service/requirements-rhlw.txt` hashes and commit before the next Lightwell PipelineRun (`--require-hashes`).

## Pipeline (dependency feed + version strings only)

Same RHHI builder/runtime as Act 3b. Only the pip index and lock change.

| | Act 3b (TL) | Lightwell mock |
|---|---|---|
| Base | RHHI | RHHI (unchanged) |
| Index | `pypi-hosted-rhtl/simple` | `pypi-hosted-rhlw/simple` |
| Lock | `requirements-t2.txt` (e.g. flask 3.1.3) | `requirements-rhlw.txt` (urllib3/jinja2/flask/gunicorn/requests `+rhlw-0001`; rest original) |
| Containerfile | `Containerfile.act3b` | `Containerfile.rhlw` |
| Image tag | `3.0.0-act3b` | `3.0.0-rhlw` |
| GitOps / promote | yes | **yes** (full E2E -- pins dev, Conforma, promote MR) |

```bash
# After files are on the git revision you pass (usually main):
oc -n fxrate-ci apply -f cluster/tekton/tasks/pytest-pip-audit.yaml
oc -n fxrate-ci apply -f cluster/tekton/pipeline-lightwell.yaml
oc -n fxrate-ci create -f cluster/tekton/pipelinerun-lightwell.yaml

oc -n fxrate-ci get pr -l demo.fxrate.index=lightwell-mock --sort-by=.metadata.creationTimestamp
```

Proof after build:

```bash
IMG=quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service:3.0.0-rhlw
# from a debug pod or toolbox with the image:
#   pip show urllib3  -> Version: 1.26.14+rhlw-0001
```

Test task installs **app** deps from the RHLW index and **pytest/pip-audit** from `pypi-proxy-pypi` (`PIP_TOOLING_INDEX_URL`).

## Smoke (local / bastion)

```bash
curl -sk "${NEXUS_RHLW_SIMPLE:-https://nexus.apps.<YOUR_CLUSTER_DOMAIN>/repository/pypi-hosted-rhlw/simple}/urllib3/"

python3 -m venv /tmp/rhlw-venv && source /tmp/rhlw-venv/bin/activate
pip install --index-url "${NEXUS_RHLW_SIMPLE}" --no-deps \
  -r fx-rate-service/requirements-rhlw.txt
pip show urllib3 jinja2 flask gunicorn requests
# expect all five +rhlw-0001: urllib3 1.26.14, jinja2 3.1.2, flask 2.2.2,
# gunicorn 20.1.0, requests 2.28.2 — 7 of 7 Vulnerable CVEs covered
```

## Talk track (Mode L standalone -- ~15-20 min)

Full beat sheet: [REHEARSAL.md](REHEARSAL.md) section Mode L.

> "ExploitIQ scanned 47 CVEs and found **7 exploitable** — 4 in urllib3, plus jinja2, Flask, and gunicorn. We can't upgrade Flask to 3.1.3 — it breaks the app. Lightwell backports **every** package with an exploitable CVE: `urllib3==1.26.14+rhlw-0001`, `jinja2==3.1.2+rhlw-0001`, `flask==2.2.2+rhlw-0001`, `gunicorn==20.1.0+rhlw-0001`, `requests==2.28.2+rhlw-0001`. Same versions, patched. **7 of 7 CVEs covered. No code changes.**"

Then: ExploitIQ (7 Vulnerable / 42 not affected) -> why upgrade breaks -> Nexus index -> PipelineRun -> `pip show urllib3 jinja2 flask gunicorn requests` -> `+rhlw-0001` on all five, flask stays `2.2.2` (not upgraded to 3.1.3) -> same Trusted Pipeline evidence (sign, ACS, SBOM, TPA, GitOps, Conforma, promote MR) -> product close (Deep Agent + Lightwell Network).

### Honesty (say out loud)

- Lab mock = **versioning + feed + pipeline shape**. Wheels are repacked Act 0 bytes, **not** real Lightwell patches.
- **pip-audit still finds CVEs** on the rhlw image by design -- proof is the version/build id + green Trusted Pipeline, not a clean audit.
- Pipeline pins **dev** to the rhlw image and opens a **promote MR** for prod (same E2E as Mode A). To restore Act 3b resting state after the demo: `RESET_CONFIRM=yes make restore-act3b`.

Lead with **urllib3** (4 Vulnerable CVEs) -- the highest-priority package. Then **Flask** (CVE-2026-27205 — "patched without upgrading to 3.1.3"), **jinja2** (CVE-2024-34064), and **gunicorn** (CVE-2024-1135). requests is also backported defensively. All 7 Vulnerable CVEs covered, 8 packages untouched -- show this contrast. Never demo `3.1.3+rhlw`.

## Files

| Path | Role |
|---|---|
| `cluster/nexus/mock-lightwell/populate-mock-lightwell.sh` | Create repo + purge + upload |
| `cluster/nexus/mock-lightwell/repack_rhlw_wheel.py` | Version rewrite |
| `cluster/nexus/mock-lightwell/packages.txt` | Act 0 upstream versions to mock |
| `fx-rate-service/requirements-rhlw.txt` | Hashed demo pins |
| `fx-rate-service/Containerfile.rhlw` | RHHI + RHLW index build |
| `cluster/tekton/pipeline-lightwell.yaml` | Pipeline (full E2E: GitOps + Conforma + promote MR) |
| `cluster/tekton/pipelinerun-lightwell.yaml` | Example run |
