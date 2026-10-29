# EgressFirewall (V-08) + ACS signature enforce (O-8)

**Reference check (pzp56 / parasol):** No `EgressFirewall` objects in parasol namespaces. ACS has the default **“Red Hat images must be signed by a Red Hat release key”** policy (disabled) plus a built-in **Red Hat** cosign signature integration — not a custom app-key enforce path. Pipeline parity we already ported (Sonar → ACS check → TPA → Conforma) is separate from these two ops controls.

---

## 1. EgressFirewall on `fxrate-ci` — **applied**

Manifest: [`cluster/network/egressfirewall-fxrate-ci.yaml`](../network/egressfirewall-fxrate-ci.yaml)

| Rule | Host / CIDR |
|---|---|
| Deny | `pypi.org`, `files.pythonhosted.org`, `packages.redhat.com` |
| Allow | `0.0.0.0/0` and `::/0` (Quay, GitLab, Nexus, RHHI, ACS, OSV, …) |

**Verified (2026-10-03):** from a probe pod in `fxrate-ci`, direct PyPI/TL hosts time out (`curl` exit 28); Nexus + Quay return HTTP 200.

```bash
oc apply -f cluster/network/egressfirewall-fxrate-ci.yaml
```

Talk track: “Build pods cannot reach PyPI or Trusted Libraries directly — packages flow through Nexus.”

**pip-audit:** default vulnerability service hits `pypi.org` and fails under this firewall. Task `pytest-pip-audit` uses `--vulnerability-service osv` (OSV is allowed). Packages still install via Nexus.

---

## 2. ACS Cosign signature policy — **integration + INFORM**

Script: [`cluster/policies/acs-enable-signature-enforce.sh`](../policies/acs-enable-signature-enforce.sh)

Mirrors the reference RH policy shape:

1. Signature integration with `cluster/policies/cosign.pub` (Chains/cosign key)
2. Policy: Quay registry + `fxrate/fx-rate-service` + **Image Signature Verified By** that integration
3. Scope: `fxrate-prod` only

| Item | Lab value (2026-10-03) |
|---|---|
| Integration | `fxrate-ci Chains cosign` (`io.stackrox.signatureintegration.96d9907e-…`) |
| Policy | `fxrate images must be signed by demo cosign key` (`5ced24f1-…`) |
| Enforcement | **empty (inform)** — do not flip until ACS shows `signatureVerificationData` |

**Why enforce is not on yet**

- Quay **does** hold Act 3b `.sig` / `.att` tags (current pin `sha256-6e235060….sig`; earlier `fbefbfd3` / `423ada` still present).
- Central’s image record still has `signature: null` / `signatureVerificationData: null` after adding the integration and a credentialed Quay registry integration.
- Enabling deploy enforce while Central cannot verify would risk blocking the signed Act 3b prod deploy.

```bash
# Already run once (inform). Re-run after signatures appear in Central:
ACS_ENFORCE=0 ./cluster/policies/acs-enable-signature-enforce.sh
# Only when Act 3b image shows non-null signatureVerificationData:
ACS_ENFORCE=1 ./cluster/policies/acs-enable-signature-enforce.sh
# then if needed:
oc -n rhacs-operator rollout restart deploy/sensor deploy/admission-control
```

**Act 4 today still stands** on **Fixable Severity at least Important** enforce for legacy reject.

---

## Honest stage lines

| Control | Say |
|---|---|
| Egress | “CI cannot talk to PyPI/TL directly; Nexus is the only package path.” |
| Signatures | “Pipeline signs with cosign; ACS has our public key and an inform policy. Severity enforce already stops legacy on prod; signature *admission* enforce is the next flip once Central ingests the Quay `.sig`.” |
