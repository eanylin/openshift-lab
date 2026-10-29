# Rehearsal -- reset, CI/CD, promote, ExploitIQ, Lightwell

**Where:** your lab bastion, or a laptop with `oc` + `digests.env`.
**Repo root:** `python-cve-upgrade-demo/`
**Stage order / URLs:** [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md)

Four modes. **Talk day = Mode A** (upgrade story, do not reset). **Dress rehearsal = Mode B** (reset -> walk -> restore). **CI/CD only = Mode C**. **Lightwell standalone = Mode L** (backport demo, separate from the upgrade story -- [LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md)).

---

## Mode A -- talk day (~30 min, no reset)

Resting cluster: Act 3b on **dev and prod**. Narrate Acts 0-2 from Quay / scripts; live-click 3b, promote, ACS, ExploitIQ.

1. Pre-show checklist in DEMO-RUNBOOK (digests, `/versions`, verify ExploitIQ results).
2. Beats 1-4: scripts + slides (`act1-rebuild-fails.sh`, `act2-chain-fails.sh`, ACS Act 2 vs 3a).
3. Beat 5: live **dev** UI + optional hash-fail (`make -C fx-rate-service act3b-hash-fail`).
4. Beat 6: GitLab promote MR (or last merged MR) + ACS legacy probe -- [ACT4.md](ACT4.md).
5. Beat 7: ExploitIQ OptB **7 Vulnerable** CVEs vs Act 3b Not Vulnerable -- results already in DB.

Then stop. Cluster stays Act 3b on GitOps. For the Lightwell backport story, use **Mode L** (separate demo).

### Pipeline talk track (do **not** walk every task)

The CVE story is Acts 0-3b. The pipeline is **how that change becomes evidenced**. On stage, group tasks into **four customer questions** (~60-90s on the PipelineRun graph). Full table: [TEKTON.md](TEKTON.md).

| Ask | What you point at | One-line benefit |
|---|---|---|
| Is the **code** OK? | `test` (pytest + pip-audit via Nexus/OSV) . `sonar-scan` | Tests + known CVE in *this* lock; Sonar is quality hygiene, not the CVE plot |
| Is the **image** OK? | `build-and-push` . `acs-scan` / `acs-check` | RHHI+TL build; ACS records findings (soft-fail in Act 3b so OS noise doesn't kill the talk) |
| Can we **prove** it later? | `sign-sbom` . CDX -> **TPA** . Chains/TAS **Rekor** . **Conforma** | Signed image + SPDX; SBOM in Trustification; SLSA in Rekor; EC `@minimal` before promote |
| Did it reach **prod** with a record? | `update-gitops` (dev only) . **promote MR** | Dev auto-syncs; prod only after a human merge (FSI/gov) |

**Leave for Q&A:** clone, webhook plumbing, ACS signature **inform**.
**Honest:** RHHI/TL/pip-audit do **not** backport PyPI CVEs; ACS Important+ **enforce** is the prod gate, not the pipeline scan.

---

## Mode B -- cold rehearsal (from "original" cluster state)

### B0. Guardrails

- `RESET_CONFIRM=yes` is required.
- Reset/restore commits include **`[skip ci]`** so the GitLab webhook does **not** rebuild Act 3b over Act 0.
- Need `fx-rate-service/digests.env` (copy from `.example` if missing).
- Dry-run first:

```bash
RESET_CONFIRM=yes DRY_RUN=1 make reset
RESET_CONFIRM=yes DRY_RUN=1 make restore-act3b
```

### B1. Reset to Act 0

```bash
RESET_CONFIRM=yes make reset
```

Expect:

| Piece | After reset |
|---|---|
| `fxrate-dev` | `1.0.0-legacy` (OptB) -- `/versions` flask **2.2.2** |
| `fxrate-prod` | **empty** (overlay pruned) |
| Git `main` | GitOps pin Act 0 (`demo: reset ... [skip ci]`) |

Show inherited pins: `fx-rate-service/legacy/requirements.txt`. Dev UI = the mess.

### B2. Acts 1-3a (scripts, not a full rebuild)

Do **not** wait for a pipeline here.

| Beat | Command / show |
|---|---|
| Act 1 | `bash cluster/demo/act1-rebuild-fails.sh` -> Werkzeug `url_quote` |
| Act 2 | `bash cluster/demo/act2-chain-fails.sh` then Quay `2.0.0-act2` |
| Act 3a | ACS OS noise Act 2 vs 3a; `oc rsh` fails on RHHI -- [ACT3a.md](ACT3a.md) |

Talk track: pinning != patchable; then interpreter/base.

### B3. Restore Act 3b (Trusted Libraries + prod)

```bash
RESET_CONFIRM=yes make restore-act3b
```

Expect **dev and prod** on `FXRATE_ACT3B_DIGEST` from `digests.env` (E2E 2026-10-11: `2074efc3...`).
`curl` both UIs: flask 3.1.3 / requests 2.34.2.

Optional live proof: `make -C fx-rate-service act3b-hash-fail` (T1 lock vs TL hashes).

### B4. CI/CD (Dev Spaces or laptop)

Stay on Act 3b. One **app** change (not docs-only, no `[skip ci]`):

1. Open Dev Spaces factory URL ([DEVSPACES.md](DEVSPACES.md)) **or** laptop clone.
2. Tiny edit under `fx-rate-service/` (comment or README in the app tree if you must not change behavior -- **docs-only at repo root may still run the pipeline** unless the commit message has `[skip ci]`).
3. `git push origin main`.
4. Watch:

```bash
oc -n fxrate-ci get pr -l demo.fxrate.trigger=gitlab-push --sort-by=.metadata.creationTimestamp
```

Path: clone -> test (OSV pip-audit) -> Sonar -> buildah -> sign -> ACS -> TPA -> **pin dev** -> validate (Conforma) -> **open prod MR**.

5. Argo `fx-rate-dev` auto-syncs the new digest. **Prod does not move yet.**

### B5. Promote (FSI/gov)

1. GitLab -> Merge requests -> **Promote 3.0.0-act3b to production**.
2. Merge (human = change record).
3. Argo `fx-rate-prod` auto-syncs. Confirm:

```bash
oc -n fxrate-prod get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -sk https://fx-rate-service-fxrate-prod.apps.<YOUR_CLUSTER_DOMAIN>/healthz
```

### B6. ACS guardrail

```bash
# Expect DENY (Important+). Digest from FXRATE_LEGACY_ACS_PROBE_DIGEST in digests.env.example
oc -n fxrate-prod run legacy-acs-probe --restart=Never \
  --image="quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service@${FXRATE_LEGACY_ACS_PROBE_DIGEST:-sha256:6aaa1e65120270f54e9388561d4a4af63ff1d899f137be135c97499a778b72b3}" \
  --command -- sleep 10
```

Delete the probe if it somehow created. Do **not** merge a "promote legacy" MR.

### B7. ExploitIQ coda

UI: SBOMs -> `fx-rate-service-legacy-optB` shows **7 Vulnerable** CVEs (urllib3 ×4, jinja2, Flask, gunicorn). Contrast Act 3b **Not Vulnerable**.
Details: [ACT0-EXPLOITIQ.md](ACT0-EXPLOITIQ.md).

### B8. Leave the lab restorable

If CI left **dev ahead of prod**, either merge the new promote MR or:

```bash
RESET_CONFIRM=yes make restore-act3b
```

so both namespaces match `digests.env` Act 3b.

---

## Mode C -- CI/CD only (no Act 0)

Skip B1-B3. From current Act 3b resting state, do **B4 -> B5 -> B6 -> B7**. Fastest way to rehearse webhook + MR promote.

---

## Mode L -- Lightwell standalone (~15-20 min)

Standalone demo of **Lightwell backport** -- no dependency on the Act 3b upgrade story. Use when the audience cares about "stay on the version you're stuck on" rather than "upgrade to the latest."

The pipeline is **identical in shape** to Mode A: test -> sonar -> build -> sign -> ACS -> SBOM -> TPA -> **GitOps pin dev** -> **Conforma** -> **promote MR**. Full SALA L3 end-to-end. Running it **will move dev** to the rhlw image and open a prod promote MR.

### L0. Pre-show

```bash
# Nexus index must have the rhlw wheels
curl -sk https://nexus.apps.<YOUR_CLUSTER_DOMAIN>/repository/pypi-hosted-rhlw/simple/urllib3/ \
  | grep -o 'urllib3-1.26.14+rhlw[^"]*' | head -1
# expect urllib3-1.26.14+rhlw_0001-py2.py3-none-any.whl
# if 404 -> bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh

# ExploitIQ: all 47 CVEs already scanned — 7 Vulnerable, no seeding needed.
# Verify: UI -> SBOMs -> fx-rate-service-legacy-optB -> 7 Vulnerable

# Apply pipeline/task if not already present
oc -n fxrate-ci apply -f cluster/tekton/tasks/pytest-pip-audit.yaml
oc -n fxrate-ci apply -f cluster/tekton/pipeline-lightwell.yaml
```

### L1. Discover the problem (~3 min)

**L1a. The vulnerable app (~1 min)**

1. Open `fx-rate-service/legacy/requirements.txt`: four pins (`flask==2.2.2`, `requests==2.28.2`, `urllib3`, `gunicorn`).
2. Point at Quay `1.0.0-legacy` or narrate: "This image ships known CVEs -- CVE-2023-30861 (Flask), CVE-2024-35195 (requests)."

**L1b. Tools confirm the problem (~2 min)**

3. **TPA**: Open Trustification, show the OptB SBOM (stage label `legacy-optB`). Flask 2.2.2 and requests 2.28.2 appear with known CVEs in the software bill of materials.
4. **ExploitIQ**: Open SBOMs → `fx-rate-service-legacy-optB`. Show **7 Vulnerable** out of 47 scanned:
   - **urllib3** (4 CVEs): "Four exploitable CVEs in one package — clearly the top priority."
   - **jinja2** (CVE-2024-34064): "XSS via `xmlattr` filter — template injection is **reachable**."
   - **Flask** (CVE-2026-27205): "Flask 2.2.2 is exploitable — but upgrading to 3.1.3 breaks the app."
   - **gunicorn** (CVE-2024-1135): "HTTP Request Smuggling — exploitable."
5. Say: **"ExploitIQ found 7 exploitable CVEs out of 47 — and 42 that are NOT exploitable. That's the signal: don't chase all 47, fix the ones that matter. But we can't upgrade Flask to 3.1.3 — it breaks the app. Lightwell patches all of them."**

### L2. Why upgrade is not an option (~1 min)

Briefly show or narrate the breakage:

- Script: `bash cluster/demo/act1-rebuild-fails.sh` -> `ImportError: cannot import name 'url_quote' from 'werkzeug.urls'`
- Or slide / narrate: "Newer Flask depends on a Werkzeug that removed `url_quote`. Upgrading breaks the app. Re-platforming takes months."

### L3. Lightwell: backport, not upgrade (~2 min)

Open the Nexus simple index in a browser (or curl):

```bash
curl -sk https://nexus.apps.<YOUR_CLUSTER_DOMAIN>/repository/pypi-hosted-rhlw/simple/urllib3/
```

Point at `urllib3-1.26.14+rhlw_0001`. Say:

> "Same project name -- `urllib3`. Same upstream version -- `1.26.14`. Lightwell adds a remediating build suffix: `+rhlw-0001`. The app code doesn't change. `pip install urllib3==1.26.14+rhlw-0001` drops in with **no code changes**."

Show `requirements-rhlw.txt` side by side with `legacy/requirements.txt` -- urllib3, jinja2, flask, gunicorn, and requests have the `+rhlw-0001` suffix (all 7 of 7 ExploitIQ Vulnerable CVEs covered). The other 8 packages stay at their original versions.

### L4. Trusted Pipeline proof (~5-8 min)

Live-run the pipeline (or show last-green):

```bash
oc -n fxrate-ci create -f cluster/tekton/pipelinerun-lightwell.yaml
oc -n fxrate-ci get pr -l demo.fxrate.index=lightwell-mock --sort-by=.metadata.creationTimestamp
```

Walk the pipeline graph -- **same shape as Mode A** (identical SALA L3):

| Task group | What it proves |
|---|---|
| `test` | pytest passes + pip-audit runs (soft-fail -- mock wheels, not real patches) |
| `build-and-push` | RHHI base + rhlw deps -> Quay `3.0.0-rhlw` |
| `sign-sbom` / ACS / TPA | Signed image, SBOM in Trustification, SLSA in Rekor |
| `update-gitops` | Pins **dev** overlay to the rhlw digest; Argo auto-syncs |
| `trigger-validation` -> Conforma -> promote MR | EC `@minimal` validation; opens **prod promote MR** |

Prove the version in the built image:

```bash
PR=$(oc -n fxrate-ci get pr -l demo.fxrate.index=lightwell-mock \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
DIGEST=$(oc -n fxrate-ci get tr "${PR}-build-and-push" \
  -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}')
oc -n fxrate-ci run rhlw-show --rm -i --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"rhlw-show","image":"quay.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/fx-rate-service@'"${DIGEST}"'","command":["/opt/venv/bin/pip","show","urllib3","jinja2","requests","flask","gunicorn"]}]}}' \
  --image=unused
# expect urllib3 1.26.14+rhlw-0001 / jinja2 3.1.2+rhlw-0001 / flask 2.2.2+rhlw-0001
# gunicorn 20.1.0+rhlw-0001 / requests 2.28.2+rhlw-0001 — all 5 backported
```

After the pipeline completes: dev UI `/versions` shows 13 packages — 5 with `+rhlw-0001` (urllib3, jinja2, flask, gunicorn, requests), 8 at original versions. Flask stays `2.2.2` (not 3.1.3). GitLab has a promote MR for prod.

### L5. Product close (~1 min)

> "Deep Agent + Lightwell Network productize this pattern. The agent opens the bump MR; ACM handles fleet. Lab uses pip-legal `+rhlw-0001`; product docs show `.rhlw-00001`. Same Trusted Pipeline evidence -- signed, attested, governed -- on a version line you already run."

### Honesty (say out loud)

- Lab mock = **versioning + feed + pipeline shape**. Wheels are repacked Act 0 bytes, **not** real Lightwell patches.
- **pip-audit still reports CVEs** on the rhlw image by design -- proof is the version/build id + green Trusted Pipeline, not a clean audit.
- Pipeline pins **dev** and opens a **promote MR** for prod (same full E2E as Mode A).

### After Mode L -- restore Act 3b resting state

```bash
RESET_CONFIRM=yes make restore-act3b
```

This puts dev and prod back on Act 3b (`3.1.3`) so the upgrade demo (Mode A) is ready again.

Details: [LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md).

---

## Timing cheat-sheet

| Block | Clock |
|---|---|
| Reset / restore | ~2-5 min each (+ Argo) |
| Act 1-2 scripts | ~5 min |
| Full Act 3b PipelineRun | ~10-15 min |
| Validate + MR appear | a few minutes after Act 3b |
| ExploitIQ seed | ~1 min |
| Mode L standalone Lightwell | ~15-20 min (problem + backport + full E2E pipeline + promote MR) |

## If something fights you

| Symptom | Likely cause |
|---|---|
| Reset, then Act 3b runs and overwrites legacy | Webhook fired -- commit missing `[skip ci]` |
| `pip-audit` / `pypi.org` unreachable | EgressFirewall -- task must use `--vulnerability-service osv` |
| Promote MR "cannot be merged" | GitLab still `checking` -- wait 10s and retry |
| ExploitIQ Not Vulnerable on OptB | Results pruned / DB wipe -- re-scan CVEs from UI, or use fallback seed script in `cluster/exploitiq/` |
| Prod ACS denies Act 3b | Cosign **enforce** flipped too early -- leave signature policy **inform** |
| RHLW `test` fails on `pytest` not found | Task missing `PIP_TOOLING_INDEX_URL` -> re-apply `pytest-pip-audit.yaml`; tooling must be `pypi-proxy-pypi` |
| Act 3b `test` / pip `errno 101` to `packages.redhat.com` | Still on `raw-proxy-rhtl`? Switch to hosted T2: `bash cluster/nexus/hosted-rhtl/populate-hosted-rhtl.sh`, re-apply `pipeline-act3b.yaml` (default index `pypi-hosted-rhtl/simple`). |
| Nexus UI missing `pypi-hosted-rhlw` / `pypi-hosted-rhtl` | Hosted repos lost with Nexus data -- re-run both populate scripts; refresh `requirements-rhlw.txt` hashes ([LIGHTWELL-MOCK.md](LIGHTWELL-MOCK.md), [BOOTSTRAP.md](BOOTSTRAP.md)) |
| Lightwell build hash mismatch / `REQUIREMENT` digests | Lock still has pre-restore hashes -- regenerate from live `pypi-hosted-rhlw` after populate |
| Docs/Lightwell commit rebuilds Act 3b | Commit message missing `[skip ci]` |
