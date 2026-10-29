#!/usr/bin/env bash
# Install Tekton Triggers listener + GitLab webhook for main-branch pushes.
# Flow: DevSpaces (or laptop) → git push main → webhook → fx-rate-act3b PipelineRun
#
# Usage (oc logged in as cluster-admin / enough rights):
#   bash cluster/tekton/setup-triggers.sh
set -euo pipefail

NS="${FXRATE_CI_NS:-fxrate-ci}"
GITLAB_HOST="${GITLAB_HOST:-gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>}"
PROJECT_PATH="${GITLAB_PROJECT_PATH:-fxrate/python-cve-upgrade-demo}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

command -v oc >/dev/null || die "oc not found"
oc whoami >/dev/null || die "oc not logged in"
oc get ns "$NS" >/dev/null

# Webhook shared secret (GitLab X-Gitlab-Token ↔ interceptor)
if ! oc -n "$NS" get secret gitlab-webhook-secret >/dev/null 2>&1; then
  TOKEN="$(openssl rand -hex 24)"
  oc -n "$NS" create secret generic gitlab-webhook-secret \
    --from-literal=token="$TOKEN"
  oc -n "$NS" label secret gitlab-webhook-secret app.kubernetes.io/part-of=fx-rate-demo --overwrite
  log "created gitlab-webhook-secret"
else
  TOKEN="$(oc -n "$NS" get secret gitlab-webhook-secret -o jsonpath='{.data.token}' | base64 -d)"
  log "reusing existing gitlab-webhook-secret"
fi

log "applying EventListener / TriggerBinding / TriggerTemplate / Route"
oc apply -f "${ROOT}/cluster/tekton/triggers/fx-rate-listener.yaml"

# Wait for EL service
for i in $(seq 1 30); do
  if oc -n "$NS" get svc el-fx-rate-listener >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
oc -n "$NS" rollout status deploy/el-fx-rate-listener --timeout=120s || true

HOOK_URL="https://$(oc -n "$NS" get route fx-rate-listener -o jsonpath='{.spec.host}')"
log "listener URL: $HOOK_URL"

GITLAB_TOKEN="${GITLAB_TOKEN:-}"
if [[ -z "$GITLAB_TOKEN" ]]; then
  GITLAB_TOKEN="$(oc -n gitlab get secret root-user-personal-token -o jsonpath='{.data.token}' | base64 -d)"
fi

PROJECT_ENC="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PROJECT_PATH")"
API="https://${GITLAB_HOST}/api/v4/projects/${PROJECT_ENC}/hooks"

# Remove existing hooks that point at our listener host
curl -sk --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$API" -o /tmp/fxrate-hooks.json
HOOK_URL="$HOOK_URL" API="$API" GITLAB_TOKEN="$GITLAB_TOKEN" python3 - <<'PY'
import json, os, urllib.request, ssl
hooks = json.load(open("/tmp/fxrate-hooks.json"))
token = os.environ["GITLAB_TOKEN"]
api = os.environ["API"]
host = os.environ["HOOK_URL"].split("/")[2]
ctx = ssl._create_unverified_context()
for h in hooks:
    url = h.get("url") or ""
    if host in url or "fx-rate-listener" in url:
        req = urllib.request.Request(f"{api}/{h['id']}", method="DELETE")
        req.add_header("PRIVATE-TOKEN", token)
        try:
            urllib.request.urlopen(req, context=ctx)
            print(f"deleted old hook {h['id']} {url}")
        except Exception as e:
            print("delete warn", e)
PY

# Create push hook (main filtered in EventListener CEL)
curl -sk --fail --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --data-urlencode "url=${HOOK_URL}" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "push_events=true" \
  --data-urlencode "tag_push_events=false" \
  --data-urlencode "enable_ssl_verification=false" \
  "$API" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("hook id=", d.get("id"), "url=", d.get("url"))'

cat <<EOF

Done.

DevSpaces factory (open repo in IDE):
  https://devspaces.apps.<YOUR_CLUSTER_DOMAIN>/#https://${GITLAB_HOST}/${PROJECT_PATH}

Flow:
  edit in DevSpaces → commit → push main → webhook → PipelineRun fx-rate-act3b-push-*

Watch:
  oc -n ${NS} get pipelinerun -l demo.fxrate.trigger=gitlab-push -w
EOF
