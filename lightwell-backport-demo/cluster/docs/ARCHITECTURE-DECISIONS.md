# Architecture decisions (why we built it this way)

**Audience:** future us + FSI/gov Q&A.  
**Last updated:** 2026-10-03

This is the memory of *choices*, not a full changelog. Stage order stays in [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md).

---

## ADR-001 — Monorepo (app + GitOps + cluster kit)

**Decision:** Keep `fx-rate-service/`, `fx-rate-gitops/`, and `cluster/` in one GitLab project.  
**Why:** One clone for Dev Spaces and pipelines; simpler for a small team than dual remotes.  
**Trade-off:** Spec appendix originally sketched two repos; we amended to monorepo in spec v0.2.

---

## ADR-002 — No RHDH; Dev Spaces as the IDE

**Decision:** Do **not** require Red Hat Developer Hub. Use **OpenShift Dev Spaces** + Git.  
**Why:** Customer has few developers, not an “army”; they still need an IDE. RHDH software catalogs add little for this CVE story.  
**Flow:** Dev Spaces → `git push main` → GitLab webhook → Tekton EventListener → Act 3b.  
**Docs:** [DEVSPACES.md](DEVSPACES.md) · `devfile.yaml` · `cluster/tekton/setup-triggers.sh`

---

## ADR-003 — Prod promote via GitLab MR (not manual Argo sync)

**Decision:** Align with parasol `update-prod-manifest`: after Conforma, open an MR that pins **prod only**; merge → Argo auto-syncs `fx-rate-prod`.  
**Why:** FSI/Government will ask for an auditable change record. Console-only “Sync” is weaker than MR + merge.  
**Mechanics:**
- `overlays/dev` digest updated by CI (`update-gitops-digest`) → auto-sync **dev**
- `overlays/prod` digest updated only on promote branch (`open-prod-promote-mr`) → merge → auto-sync **prod**
- Base Deployment uses `:overlay-pin`; digests live in overlay `images:`

**Rejected alternative:** Shared base digest + manual Argo sync (earlier P0 semi-auto) — fine for speed, weak for regulated Q&A.

---

## ADR-004 — Parasol pipeline parity without Maven / 3-pipeline split

**Decision:** Port secured stages (Sonar, ACS scan/check, CDX→TPA, wait-attestation, Conforma, Chains→TAS Rekor) into **Act 3b + validate**, not a full Maven push/tag-promote trilogy.  
**Why:** Teaching point is Python CVE chain + Trusted Libraries, not Java build shape.  
**Reference check (pzp56):** No EgressFirewall; ACS Important+ not scoped to prod; Dev Spaces + RHDH present — we took IDE+webhook and MR promote, skipped RHDH.

---

## ADR-005 — EgressFirewall on `fxrate-ci` (beyond reference)

**Decision:** Deny direct `pypi.org` / `files.pythonhosted.org` / `packages.redhat.com` from CI.  
**Why:** Constitution III — packages must go through Nexus; reference parasol did not enforce this.  
**Follow-on:** `pip-audit` default advisory service hits `pypi.org` — use `--vulnerability-service osv` (OSV allowed).  
**Docs:** [EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md)

---

## ADR-006 — ACS Important+ enforce; cosign signature inform

**Decision:** Enforce **Fixable Severity at least Important** on `fxrate-prod`. Wire cosign signature integration + policy in **inform** until Central shows `signatureVerificationData` on Act 3b.  
**Why:** Quay has `.sig` / `.att`, but Central still reports `signature: null` — flipping deploy enforce could block the signed Act 3b image.  
**Docs:** [ACS-ACT4.md](../policies/ACS-ACT4.md), [EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md)

---

## ADR-007 — ExploitIQ: natural results, no seeding needed

**Decision:** All 47 CVEs scanned via UI — 7 Vulnerable naturally. Use ExploitIQ as single pane of glass; no pre-seeding required.  
**Why:** Full scan completed; results persist in MongoDB. Seed script kept as fallback only (cluster/exploitiq/).  
**Supersedes:** Previous decision to pre-seed CVE-2024-35195 via `seed-optb-vulnerable-report.sh`.  
**Docs:** [ACT0-EXPLOITIQ.md](ACT0-EXPLOITIQ.md)

---

## ADR-008 — `make reset` / `make restore-act3b`

**Decision:** Scripted GitOps reset to Act 0 (legacy on dev, empty prod) and restore to Act 3b pins.  
**Why:** Spec FR-040 / constitution IX; resting lab is Act 3b for talks, reset for cold rehearsals.  
**Requires:** `RESET_CONFIRM=yes`, `digests.env`, `oc`, `git push`.

---

## ADR-009 — Trusted Libraries via Nexus **raw** proxy (+ hosted T2 for CI)

**Decision:** Fetch TL through `raw-proxy-rhtl` (not PyPI-format `pypi-proxy-rhtl`). Act 3b **CI/build** installs from hosted `pypi-hosted-rhtl` (same wheel bytes, relative URLs).  
**Why:** TL simple root has no `/simple/` segment; Nexus PyPI proxy cannot map it (V-03 / O-3 closed). Raw simple pages point at absolute `packages.redhat.com` URLs that flake from `fxrate-ci`; hosted mirror keeps constitution III (no PyPI fallback) while staying on Nexus only.

---

## Doc map (keep these consistent)

| Doc | Owns |
|---|---|
| [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md) | Stage order + pre-show |
| [ARCHITECTURE-DECISIONS.md](ARCHITECTURE-DECISIONS.md) | **Why** (this file) |
| [GOALS.md](../../GOALS.md) | Status / open vs closed |
| [DEVSPACES.md](DEVSPACES.md) | IDE + webhook |
| [ACT4.md](ACT4.md) | Promote MR + ACS |
| [EGRESS-AND-SIGNATURES.md](EGRESS-AND-SIGNATURES.md) | V-08 + signature policy |
| [TEKTON.md](TEKTON.md) | Pipeline shape |
| [BOOTSTRAP.md](BOOTSTRAP.md) | Fresh lab install |
