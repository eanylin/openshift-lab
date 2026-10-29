# ACS policy notes for Act 4 (MR promote + admission enforce)

**Cluster:** RHACS 4.11.4 on `hub-cluster`, HEALTHY. Validating webhook `stackrox` / `policyeval.stackrox.io` present.

## Target for the demo

| Namespace | Mode | Intent |
|---|---|---|
| `fxrate-dev` | Inform (outside prod scope) | Iterate without blocking |
| `fxrate-prod` | **Enforce** | Reject `1.0.0-legacy` (fixable Important+) |

## Policies wired (2026-10-01)

- [x] **Fixable Severity at least Important** (`a919ccaf-6b43-4160-ac5d-a405e1440a41`)
  - Scope: `[{"namespace":"fxrate-prod"}]` *(namespace-only; avoid `cluster=` name quirks)*
  - Enforcement: `FAIL_BUILD_ENFORCEMENT`, `FAIL_DEPLOYMENT_CREATE_ENFORCEMENT`, `FAIL_DEPLOYMENT_UPDATE_ENFORCEMENT`, `SCALE_TO_ZERO_ENFORCEMENT`
- [x] Cosign signature integration + policy **inform** — `acs-enable-signature-enforce.sh` (policy `5ced24f1-…`); **enforce deferred** until Central shows `signatureVerificationData` on Act 3b (Quay `.sig` exists). See [EGRESS-AND-SIGNATURES.md](../docs/EGRESS-AND-SIGNATURES.md).
- [x] Admission webhook present; after policy flips, restart `sensor` + `admission-control` if creates still succeed

## Evidence

- Legacy scan: **44** fixable Important/Critical
- Act 3a RHHI: **0** fixable Important/Critical
- Runbook: [ACT4.md](../docs/ACT4.md)

## Promote + deny flow (ADR-003)

1. CI pins **dev** only; validate opens **promote MR** for **prod** digest.
2. Merge MR → Argo `fx-rate-prod` auto-syncs.
3. Legacy create → ACS admission denies (use `FXRATE_LEGACY_ACS_PROBE_DIGEST` from `digests.env.example`).
4. Revert bad MR / pin → Healthy.

## Rollback caveat (spec §10)

Only roll between images that still pass prod policy.
