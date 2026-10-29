# Dev Spaces → GitLab → Tekton (no RHDH)

**Goal:** A few developers edit in **OpenShift Dev Spaces**, push to GitLab, and the Trusted Pipeline runs — same contract as a laptop `git push`.

```text
Dev Spaces IDE
    → commit / push `main`
    → GitLab webhook (Push Hook)
    → EventListener `fx-rate-listener` (fxrate-ci)
    → PipelineRun `fx-rate-act3b-push-*`
    → Argo auto-syncs **fxrate-dev**
    → validate opens **GitLab MR** to pin **fxrate-prod** (merge = promote)
```

## One-time setup

```bash
# Secrets / SA for pipelines (if not already)
bash cluster/tekton/setup-secrets.sh

# Triggers + GitLab webhook
bash cluster/tekton/setup-triggers.sh
```

Creates:

| Piece | Name |
|---|---|
| EventListener | `fxrate-ci/fx-rate-listener` |
| Route | `https://fx-rate-listener-fxrate-ci.apps.…` |
| Secret | `gitlab-webhook-secret` |
| GitLab hook | Push events on `fxrate/python-cve-upgrade-demo` |
| Filter | CEL: only `refs/heads/main` |

## Open the repo in Dev Spaces

Factory URL (this lab):

https://devspaces.apps.<YOUR_CLUSTER_DOMAIN>/#https://gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>/fxrate/python-cve-upgrade-demo

Or: Dev Spaces UI → **Create Workspace** → paste the GitLab clone URL.  
Repo includes [`devfile.yaml`](../../devfile.yaml) at the root.

Authenticate to GitLab when prompted (PAT or OAuth) so push works from the workspace.

## Demo click-path

1. Open workspace from the factory URL.
2. Edit something small under `fx-rate-service/` (or narrate without changing behavior).
3. Commit + push to **`main`**.
4. Show PipelineRun:
   ```bash
   oc -n fxrate-ci get pipelinerun -l demo.fxrate.trigger=gitlab-push --sort-by=.metadata.creationTimestamp
   ```
5. After success, Argo `fx-rate-dev` picks up the new digest pin.

## Notes

- **No RHDH required** — Dev Spaces is only the IDE (ADR-002).
- **Prod** changes only via the **promote MR** after Conforma (ADR-003) — not on every push.
- Pushing docs-only commits with `[skip ci]` in the message does **not** run Act 3b (Trigger CEL). Reset/restore commits include that token.
- Laptop flow is identical: same remote, same webhook.

## Manifests

- `cluster/tekton/triggers/fx-rate-listener.yaml`
- `cluster/tekton/setup-triggers.sh`
