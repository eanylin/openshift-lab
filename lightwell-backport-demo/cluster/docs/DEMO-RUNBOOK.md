# End-to-end demo runbook

**Audience:** presenter walking an OpenShift lab that already has Acts 0-4 built.
**Last aligned:** 2026-10-19 . digests in `fx-rate-service/digests.env.example`

This is the single place for *what to show, in what order*. Per-act deep dives stay in `ACT*.md`.

---

## What the audience should walk away with

1. **Pinning != patchable** -- transitive deps + Python floor + Flask API breaks (Acts 0-2).
2. **Layered fix** -- interpreter/base (3a) then provenance index (3b), neither claiming to backport PyPI CVEs.
3. **Evidence + guardrail** -- signed image / SBOM / GitOps promote; ACS stops legacy on prod (Act 4).
4. **Optional coda** -- ExploitIQ: same CVE **Vulnerable** on Option B, **Not Vulnerable** after Act 3b.

---

## Current cluster resting state (do not "reset" live)

| Namespace | Image | Notes |
|---|---|---|
| `fxrate-dev` | `3.0.0-act3b` @ `sha256:6e235060...` | Argo auto-sync from GitLab `main` |
| `fxrate-prod` | **same digest** | MR !3 merged (Sonar S6853 UI fix); ACS Important+ enforce |
| Quay | Keep **tags** `1.0.0-legacy` . `1.0.0-legacy-optA` . `2.0.0-act2` . `3.0.0-act3a` . `3.0.0-act3b`. **Do not** prune tags; lab GC already deleted untagged digests (Act 0 pull failed). Rebuild if a tag's digest 404s. |
| Git tags | `exploitiq-optA`, `exploitiq-optB`, `exploitiq-act3b` | Source refs for ExploitIQ |

### Reset / restore (optional)

```bash
# From repo root, oc logged in, digests.env present:
RESET_CONFIRM=yes make reset            # GitOps -> 1.0.0-legacy on dev; prune prod empty
RESET_CONFIRM=yes make restore-act3b    # back to Act 3b on dev + prod (resting talk state)

RESET_CONFIRM=yes DRY_RUN=1 make reset  # show what would change
```

**Full click-path (reset -> CI/CD -> promote -> ExploitIQ):** [REHEARSAL.md](REHEARSAL.md)

Scripts: `cluster/demo/reset-to-act0.sh`, `cluster/demo/restore-act3b.sh`.
Reset/restore commits use `[skip ci]` so the webhook does not rebuild Act 3b over Act 0.
For a talk without resetting the cluster, **narrate** earlier acts from Quay tags / scripts and live-click resting Act 3b + Act 4 / ExploitIQ.

---

## Recommended stage flow -- upgrade demo (~30-35 min)

| # | Beat | What you open | Live vs fallback |
|---|---|---|---|
| 1 | **Act 0 -- inherited mess** | Quay `1.0.0-legacy` or archived `/versions` (flask 2.2.2 / requests 2.28.2). Show `fx-rate-service/legacy/requirements.txt` (4 pins: flask, requests, **urllib3**, gunicorn). | Fallback: [ACT1.md](ACT1.md) artifacts |
| 2 | **Act 1 -- just rebuild** | Run or show `cluster/demo/act1-rebuild-fails.sh` -> `url_quote` ImportError | Script is the rehearsal path (no PR pipeline) |
| 3 | **Act 2 -- chain of floors** | `cluster/demo/act2-chain-fails.sh` then point at Act 2 image / [ACT2.md](ACT2.md) | Podman scripts replace toolbox pods |
| 4 | **Act 3a -- RHHI** | Compare ACS OS noise Act 2 vs 3a ([ACT3a.md](ACT3a.md)); `oc rsh` fails on RHHI | Image still in Quay |
| 5 | **Act 3b -- Trusted Libraries** | Hash-fail demo `make -C fx-rate-service act3b-hash-fail`; live **dev UI** already on 3b. Optional IDE beat: edit in **Dev Spaces** -> push `main` -> webhook runs Act 3b ([DEVSPACES.md](DEVSPACES.md)). | [ACT3b.md](ACT3b.md) |
| 6 | **Act 4 -- evidence + ACS** | Cosign / Conforma; **merge the promote MR** -> prod rolls (Git change record). Legacy probe deny ([ACT4.md](ACT4.md)). | Do **not** leave prod on a rejected legacy MR |
| 7 | **Coda -- ExploitIQ** | Open ExploitIQ → **7 Vulnerable** CVEs on OptB; contrast Act 3b Not Vulnerable | Results already in DB -- [ACT0-EXPLOITIQ.md](ACT0-EXPLOITIQ.md) |

### Pre-show checklist (15 min)

```bash
# Digests match GitOps
oc -n fxrate-dev get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
oc -n fxrate-prod get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Expect digests from overlays/dev|prod (dev often ahead until promote MR merges)

curl -sk https://fx-rate-service-fxrate-dev.apps.<YOUR_CLUSTER_DOMAIN>/versions
curl -sk https://fx-rate-service-fxrate-prod.apps.<YOUR_CLUSTER_DOMAIN>/healthz

# ExploitIQ: all 47 CVEs scanned — 7 Vulnerable (urllib3 ×4, jinja2, Flask, gunicorn).
# No seeding needed. Verify: UI -> SBOMs -> fx-rate-service-legacy-optB -> 7 Vulnerable
# If results lost (DB wipe): re-scan from UI, or fallback seed script in cluster/exploitiq/
```

---

## Standalone Lightwell demo -- Mode L (~15-20 min)

Self-contained backport story -- does not depend on Beats 1-7 or the Act 3b upgrade. **Same full SALA L3 pipeline** as Mode A (GitOps pin + Conforma + promote MR). Full rehearsal steps: [REHEARSAL.md](REHEARSAL.md) section Mode L.

| # | Beat | What you open | Notes |
|---|---|---|---|
| L1 | **Discover the problem** | `legacy/requirements.txt`; Quay `1.0.0-legacy`; **TPA** OptB SBOM; **ExploitIQ** → **7 Vulnerable** CVEs (urllib3 ×4, jinja2, Flask, gunicorn) | ExploitIQ as single pane of glass: 7 exploitable out of 47 scanned |
| L2 | **Why not upgrade** | Act 1 script or narrate `url_quote` ImportError | Newer Flask breaks the app -- re-platforming takes months |
| L3 | **Lightwell backport** | Nexus `pypi-hosted-rhlw` -> 5 packages `+rhlw-0001` (urllib3, jinja2, flask, gunicorn, requests); 8 passthrough | Same name, same upstream version, remediating build. **No code changes** |
| L4 | **Trusted Pipeline** | PipelineRun `fx-rate-lightwell`; dev UI `/versions` shows 5 `+rhlw-0001` out of 13; promote MR | Full E2E: test -> build -> sign -> ACS -> SBOM -> TPA -> **GitOps** -> **Conforma** -> **promote MR** |
| L5 | **Product close** | Deep Agent + Lightwell Network | Agent opens MR; ACM fleet; `.rhlw-00001` (docs) / `+rhlw-0001` (lab) |

**Honesty:** mock = versioning + feed + pipeline shape, not real patches. pip-audit still reports CVEs. Proof is version/build id + green pipeline.
**After demo:** `RESET_CONFIRM=yes make restore-act3b` to put dev/prod back on Act 3b.

### Pre-show checklist (Lightwell standalone)

```bash
# Nexus index
curl -sk https://nexus.apps.<YOUR_CLUSTER_DOMAIN>/repository/pypi-hosted-rhlw/simple/urllib3/ \
  | grep -o 'urllib3-1.26.14+rhlw[^"]*' | head -1
# expect urllib3-1.26.14+rhlw_0001  -- if 404, populate:
#   bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh

# ExploitIQ: all 47 CVEs scanned — 7 Vulnerable (7/7 covered by backport). No seeding needed.
# Verify: UI -> SBOMs -> fx-rate-service-legacy-optB -> 7 Vulnerable
# If results lost (DB wipe): re-scan from UI, or fallback seed script in cluster/exploitiq/

# Last-green PipelineRun
oc -n fxrate-ci get pr -l demo.fxrate.index=lightwell-mock \
  --sort-by=.metadata.creationTimestamp -o custom-columns=NAME:.metadata.name,OK:.status.conditions[0].status | tail -3
# if none green -> oc -n fxrate-ci create -f cluster/tekton/pipelinerun-lightwell.yaml

# Pipeline/task applied
oc -n fxrate-ci apply -f cluster/tekton/tasks/pytest-pip-audit.yaml
oc -n fxrate-ci apply -f cluster/tekton/pipeline-lightwell.yaml
```

---

## Lab URLs (your cluster)

| Piece | URL |
|---|---|
| Dev UI | https://fx-rate-service-fxrate-dev.apps.<YOUR_CLUSTER_DOMAIN>/ |
| Prod UI | https://fx-rate-service-fxrate-prod.apps.<YOUR_CLUSTER_DOMAIN>/ |
| Argo | https://openshift-gitops-server-openshift-gitops.apps.<YOUR_CLUSTER_DOMAIN> |
| GitLab | https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo |
| Nexus | https://nexus.apps.<YOUR_CLUSTER_DOMAIN> |
| Lightwell mock (lab) | Nexus `pypi-hosted-rhlw` (urllib3/jinja2/flask/gunicorn/requests `+rhlw-0001` — 7/7 CVEs) + pipeline `fx-rate-lightwell` -- [LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md) |

Replace hosts when cloning to another lab -- see comments in `digests.env.example` and [BOOTSTRAP.md](BOOTSTRAP.md).

---

## How acts relate to git (honest model)

| Act | How we produced it | What `main` looks like now |
|---|---|---|
| 0-1 | Legacy image + scripts; branches `act-1-rebuild` | `main` is **Act 3b app** + `legacy/` kept for narrative |
| 2 | Pipeline + branch `act-2-appfix` | Merged; image tag retained in Quay |
| 3a / 3b | Pipelines pin GitOps base digest | Base deployment = **Act 3b** digest |
| 4 | Promote MR -> Argo auto-syncs prod overlay | Prod labels `demo.fxrate.act=3b` |
| ExploitIQ | Tags `exploitiq-optB` / OptA; seed script | Do not rely on UI Submit live |

---

## Rebuild on a new lab (GitHub -> Quay -> GitOps)

1. Bootstrap namespaces, Nexus (`pypi-proxy-pypi` + **`raw-proxy-rhtl`** + hosted T2 `pypi-hosted-rhtl`), Argo apps -- [BOOTSTRAP.md](BOOTSTRAP.md).
2. `cp fx-rate-service/digests.env.example fx-rate-service/digests.env` and rewrite Quay/Nexus/Git hosts.
3. Build & push images (from `fx-rate-service/`):
   ```bash
   make legacy-image && podman push "$(FXRATE_IMAGE_REPO):1.0.0-legacy"
   make act2-image   && podman push "$(FXRATE_IMAGE_REPO):2.0.0-act2"
   make act3a-image  && podman push "$(FXRATE_IMAGE_REPO):3.0.0-act3a"
   make act3b-image  && podman push "$(FXRATE_IMAGE_REPO):3.0.0-act3b"
   ```
4. Record each **RepoDigest** into `digests.env` / `.example` and pin `fx-rate-gitops/base/deployment.yaml`.
5. Apply Tekton tasks/pipelines; `bash cluster/tekton/setup-secrets.sh` (lab-shaped -- edit for new credentials).
6. Act 4: ACS Important+ enforce on `fxrate-prod` only -- [ACS-ACT4.md](../policies/ACS-ACT4.md).
7. Optional ExploitIQ: apply `cluster/exploitiq/eiq-*-patch.yaml`, keep a known-good TRUE JSON for the seed script.

---

## Doc map

| Doc | Use when |
|---|---|
| **This file** | Stage order + pre-show |
| [REHEARSAL.md](REHEARSAL.md) | Reset -> walk CI/CD / promote / ExploitIQ / Lightwell standalone |
| [GOALS.md](../../GOALS.md) | Status / open work |
| [BOOTSTRAP.md](BOOTSTRAP.md) | Fresh cluster install |
| [DEVSPACES.md](DEVSPACES.md) | IDE -> webhook -> Tekton |
| [TEKTON.md](TEKTON.md) | Pipeline details |
| [EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md) | EgressFirewall + ACS cosign |
| [ACT0-EXPLOITIQ.md](ACT0-EXPLOITIQ.md) | ExploitIQ coda only |
| [ACT1.md](ACT1.md) ... [ACT4.md](ACT4.md) | Per-act evidence |
| [LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md) | Lightwell backport demo (Mode L) |
