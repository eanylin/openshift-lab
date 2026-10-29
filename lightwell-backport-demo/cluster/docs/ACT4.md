# Act 4 — Release with evidence (MR promote)

**Spec:** §5.6 · **Why:** [ARCHITECTURE-DECISIONS.md](ARCHITECTURE-DECISIONS.md) ADR-003  
**Talk track:** *Nothing reached production without a Git merge — policy stops legacy the same way at 3am.*

## Lab wiring (2026-10-01)

| Piece | State |
|---|---|
| ACS policy **Fixable Severity at least Important** | Enforce on **`fxrate-prod` only** (`FAIL_DEPLOYMENT_CREATE/UPDATE` + build + `SCALE_TO_ZERO`). Scope: `namespace=fxrate-prod` (do **not** set `cluster=` — name scoping alone matched reliably). |
| Policy ID | `a919ccaf-6b43-4160-ac5d-a405e1440a41` |
| Argo `fx-rate-prod` | Auto-sync ON — digest changes only when a **promote MR** merges (ADR-003) |
| Cosign | Pipeline task `cosign-sign-sbom` (syft SPDX + cosign sign/attest). Pubkey in [`cosign.pub`](../policies/cosign.pub). Secret `cosign-signing` in `fxrate-ci` (copied from Chains `signing-secrets`). |
| SBOM | SPDX JSON attached as Quay `.att` via `cosign attest --type spdxjson` (not a git file). |

**Ops note:** After flipping enforce actions, restart `sensor` + `admission-control` in `rhacs-operator` if creates are still allowed (stale policy push).

## Promote → prod (AC-4.2) — GitLab MR (FSI/gov)

Dev and prod pins are **separate** (`overlays/dev` vs `overlays/prod` digests).

1. Act 3b pipeline pins **dev** only → Argo auto-syncs `fxrate-dev`.
2. Validate (Conforma) opens a **GitLab MR** that updates the **prod** digest (`open-prod-promote-mr`).
3. Reviewer merges the MR → Argo `fx-rate-prod` **auto-syncs** (Git is the change record).

```bash
# After a validate run, open GitLab MRs titled "Promote … to production"
# Merge → watch:
oc -n openshift-gitops get application fx-rate-prod
oc -n fxrate-prod get deploy,pods
curl -sk https://fx-rate-service-fxrate-prod.apps.<YOUR_CLUSTER_DOMAIN>/healthz
```

## Prove legacy reject (AC-4.3) then revert (AC-4.4)

```bash
# Probe (expect DENY from policyeval.stackrox.io).
# Use FXRATE_LEGACY_ACS_PROBE_DIGEST from digests.env.example (older Important+ image).
oc -n fxrate-prod run legacy-acs-probe --restart=Never \
  --image="quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service@${FXRATE_LEGACY_ACS_PROBE_DIGEST:-sha256:6aaa1e65120270f54e9388561d4a4af63ff1d899f137be135c97499a778b72b3}" \
  --command -- sleep 10

# GitOps path: temporary prod patch to legacy digest → sync → admission rejects new pods.
# git revert + sync → Synced/Healthy on Act 3b digest (current resting pin).
```

Legacy inventory: **44** fixable Important/Critical. Act 3a/3b RHHI: **0**.

## Signature / SBOM (AC-4.1)

Produced by pipeline task `sign-sbom` (see [TEKTON.md](TEKTON.md)). Retrieve from Quay:

```bash
IMG=quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service@sha256:1a040eeac7a71a5b99e7232a1aaf343a70b449d2b2b01013a50f1b08a6aa3146
cosign verify --key cluster/policies/cosign.pub --allow-insecure-registry "$IMG"
cosign verify-attestation --key cluster/policies/cosign.pub --allow-insecure-registry --type spdxjson "$IMG"
```

## Acceptance

| ID | Notes |
|---|---|
| AC-4.1 | Cosign verify + SPDX attestation on Act 3a digest |
| AC-4.2 | Promote MR merge → `fxrate-prod` on validated digest (no rebuild) |
| AC-4.3 | Legacy create denied by `policyeval.stackrox.io` (Fixable Severity at least Important) |
| AC-4.4 | Revert / re-pin in Git → Argo Synced/Healthy on Act 3b |

## Verified (2026-10-01 / promote Act 3b 2026-10-03)

- Promoted `3.0.0-act3a` (`sha256:1a040eea…`) to `fxrate-prod` — `/healthz` OK; same digest as dev (2026-10-01)
- Earlier Act 3b pin `sha256:423ada46…` on prod (pre–MR path). Still a valid signed image; **not** the resting GitOps pin.
- **Resting:** `3.0.0-act3b` `@sha256:6e235060…` on **dev and prod** after [MR !3](https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo/-/merge_requests/3) (Sonar S6853). !2 was `9b44e80e…`; !1 was `fbefbfd3…`.
- Cosign signature + SPDX attestation verified with `cluster/policies/cosign.pub` (Act 3a manual; Act 3b via pipeline task `cosign-sign-sbom`)
- Pipelines Act 2/3a/3b now include `sign-sbom` after buildah (see [TEKTON.md](TEKTON.md))
- Legacy probe pod **denied** by ACS admission (44 fixable Important/Critical listed in webhook message)
- Reverted deliberate legacy GitOps pin (`5a68690`) → prod Healthy on Act 3a again (pre–Act 3b promote)

## Rollback caveat (spec §10)

Only roll between digests that still pass prod policy. Act 3a currently has **0** fixable Important+; legacy has **44**.
