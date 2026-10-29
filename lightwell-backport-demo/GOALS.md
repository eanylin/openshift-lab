# Goals & tracking — Lightwell Backport Demo

**Why:** [cluster/docs/ARCHITECTURE-DECISIONS.md](cluster/docs/ARCHITECTURE-DECISIONS.md)  
**Stage order:** [cluster/docs/DEMO-RUNBOOK.md](cluster/docs/DEMO-RUNBOOK.md)  
**Why we built it this way:** [cluster/docs/ARCHITECTURE-DECISIONS.md](cluster/docs/ARCHITECTURE-DECISIONS.md)  
**Last updated:** 2026-10-19

---

## North star

Prove on OpenShift that **pinning alone does not make a Python service patchable**, and that fixing CVEs is a **chain** (dependency graph → interpreter → base image → code) that becomes a **routine, evidenced change** when you combine:

| Layer | Capability |
|---|---|
| Hardened runtime | Red Hat Hardened Images (RHHI) — distroless, fewer OS CVEs |
| Curated index | Red Hat Trusted Libraries via Nexus **raw** proxy (provenance; no PyPI fallback) |
| Build evidence | Trusted Pipeline — signed image, SBOM, SLSA provenance, archived `pip-audit` + ACS scans |
| Delivery | OpenShift GitOps — Git is the only change path; **prod via promote MR** |
| Guardrail | RHACS — **Important+ enforce** on prod; cosign signature policy **inform** (until Central ingests `.sig`) |
| Developer path | **Dev Spaces** → GitLab webhook → Tekton (no RHDH) |

**Honest framing (constitution VIII):** RHHI does not fix PyPI package CVEs; Trusted Libraries does not backport. App-layer remediation remains an upgrade the customer owns.

**Out of scope:** Renovate/Dependabot, multi-arch/FIPS variants (optional slide), production-grade Nexus HA, **RHDH**.

**Optional coda — ExploitIQ:** Demo-ready via **seed** (not live UI Submit). See [ACT0-EXPLOITIQ.md](cluster/docs/ACT0-EXPLOITIQ.md).

**Standalone Lightwell demo (Mode L):** Backport-in-place story -- urllib3/jinja2/flask/gunicorn/requests `+rhlw-0001` backports from Lightwell (7 of 7 Vulnerable CVEs covered, flask stays 2.2.2 patched without upgrading to 3.1.3), same full SALA L3 pipeline. See [LIGHTWELL-MOCK.md](cluster/docs/LIGHTWELL-MOCK.md).

---

## Delivery strategy

| Decision | Choice | Why (ADR) |
|---|---|---|
| Layout | Monorepo | ADR-001 |
| IDE | Dev Spaces, not RHDH | ADR-002 |
| Prod promote | GitLab MR after Conforma → Argo auto-sync | ADR-003 |
| Pipeline shape | Act 3b + validate (not full Maven trilogy) | ADR-004 |
| Working copy | Local + lab GitLab | — |
| Later | Public GitHub mirror + ExploitIQ tags | — |

---

## Milestone map

| Act | Name | Status |
|---|---|---|
| Act 0 | Inherited vulnerable app | Done — Quay `1.0.0-legacy` (OptB); `legacy/` |
| Act 1 | “Just rebuild” fails (Werkzeug) | Done — [ACT1.md](cluster/docs/ACT1.md) |
| Act 2 | Python 3.12 + floors + lock + refactor | Done — [ACT2.md](cluster/docs/ACT2.md) |
| Act 3a | RHHI multi-stage | Done — [ACT3a.md](cluster/docs/ACT3a.md) |
| Act 3b | Trusted Libraries T2 | Done — [ACT3b.md](cluster/docs/ACT3b.md) |
| Act 4 | Evidence + **MR promote** + ACS legacy deny | Done — [ACT4.md](cluster/docs/ACT4.md) |
| DX | Dev Spaces + webhook Triggers | Done — [DEVSPACES.md](cluster/docs/DEVSPACES.md) |
| Coda | ExploitIQ before/after | Done (seed) — [ACT0-EXPLOITIQ.md](cluster/docs/ACT0-EXPLOITIQ.md) |
| Mode L | Lightwell standalone backport demo | Done — [LIGHTWELL-MOCK.md](cluster/docs/LIGHTWELL-MOCK.md), [REHEARSAL.md Mode L](cluster/docs/REHEARSAL.md) |

### Still open

| Tier | Item | Notes |
|---|---|---|
| P2 | Act 5 — Day-2 RHHI digest bump | Needs newer RHHI digest (V-13) |
| Ops | ACS cosign **deploy enforce** | Inform live; wait for Central `signatureVerificationData` — ADR-006 |

### Closed ops (do not re-litigate)

| Item | Where |
|---|---|
| `make reset` / `restore-act3b` | ADR-008 |
| EgressFirewall on `fxrate-ci` | ADR-005 |
| TL via `raw-proxy-rhtl` | ADR-009 |
| Prod MR promote (vs manual Argo sync) | ADR-003 |
| Lightwell mock + Mode L standalone demo | [LIGHTWELL-MOCK.md](cluster/docs/LIGHTWELL-MOCK.md) |
| Host rewrite (`set-lab-hosts.sh`) | BOOTSTRAP · `cluster/lab.env.example` |

### Lab validation (spec §8)

| ID | Notes |
|---|---|
| V-01–V-07 | Pass (see earlier notes; V-05 pip-tooling caveat) |
| V-08 | **Pass** — EgressFirewall |
| V-11 | Pass — Important+ enforce; legacy denied |
| V-12 | **Met** — `make reset` / `restore-act3b` |

---

## Repo layout

```text
python-cve-upgrade-demo/
├── GOALS.md / README.md / devfile.yaml
├── cluster/docs/
│   ├── DEMO-RUNBOOK.md              ← stage order
│   ├── ARCHITECTURE-DECISIONS.md    ← why
│   ├── DEVSPACES.md                 ← IDE + webhook
│   └── …
├── fx-rate-service/
├── fx-rate-gitops/                  ← overlays/dev|prod digest pins
└── cluster/tekton/triggers/         ← GitLab EventListener
```

---

## Non-goals

- RHDH / software catalog
- Live-clicking ExploitIQ Submit for the Vulnerable beat (use seed)
- Claiming Trusted Libraries before V-01/V-03 on a new lab
- Auto-merging promote MRs (human merge is the control)
