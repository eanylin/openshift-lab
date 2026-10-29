# Act 1 — “Just rebuild it”

**Spec:** §5.2 · **Talk track:** *The resolver said yes. The app said no.*

## What this act proves

Act 0’s image was built with the full **L0** pin set (`legacy/constraints-2023.txt`).  
What the **repo** shows (and what a naïve rebuild uses) is **R0** — three top-level pins only:

```text
flask==2.2.2
requests==2.28.2
gunicorn==20.1.0
```

A fresh `pip install` of R0 through Nexus pulls **Werkzeug 3.x**. Flask 2.2.2 then fails:

`ImportError: cannot import name 'url_quote' from 'werkzeug.urls'`

No image should be pushed or promoted.

## Acceptance criteria (lab status — verified 2026-10-01)

| ID | Criterion | Result |
|---|---|---|
| AC-1.1 | R0 via Nexus resolves Werkzeug 3.x | **Pass** — `werkzeug 3.1.9` (see `artifacts/act1-r0-install.log`) |
| AC-1.2 | Import/test fails with `url_quote`; no promote | **Pass** — `ImportError: cannot import name 'url_quote'…`; `Containerfile.act1-rebuild` build exits 1 |
| AC-1.3 | Act 0 / L0 shows Flask 2.3 deprecations | **Pass** — `app.json_encoder` + `before_first_request` (`artifacts/act1-l0-deprecations.log`); `PYTHONWARNINGS=default` on Deployment |
| AC-1.4 | Failure visible before deploy | **Pass (fallback)** — GitLab branch `act-1-rebuild` + archived logs; Tekton PR check deferred until pipeline exists |

Observed R0 resolve (Nexus): `flask 2.2.2`, **`werkzeug 3.1.9`**, `requests 2.28.2`, `urllib3 1.26.20`.

## Reproduce (fallback — no pipeline required)

On the bastion (podman + `oc` login + `digests.env`):

```bash
cd ~/python-cve-upgrade-demo   # or local clone
cp fx-rate-service/digests.env.example fx-rate-service/digests.env   # if needed
bash cluster/demo/act1-rebuild-fails.sh
# logs: /tmp/fxrate-act1/r0-install.log
#       /tmp/fxrate-act1/l0-deprecations.log
```

## Stage sequence (~5 min)

1. Show Act 0 UI still healthy; open `/versions` (L0 pins).
2. Show `fx-rate-service/legacy/requirements.txt` (R0 — only three pins).
3. Run `act1-rebuild-fails.sh` (or open archived logs). Highlight Werkzeug **3.x** then `url_quote` ImportError.
4. Show L0 deprecation warnings (warnings that were always there).
5. Close: pinning Flask did not pin Werkzeug; the 2023 image was the only true record.

## Branch

`act-1-rebuild` — narrative branch for “rebuild with same R0, newer base only”.  
Until Tekton is wired, the shell reproduction is the evidence artifact.
