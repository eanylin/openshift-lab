#!/usr/bin/env bash
# Create fxrate-ci ServiceAccount, SCCs, and Tekton workspace secrets.
set -euo pipefail

NS="${FXRATE_CI_NS:-fxrate-ci}"
GITLAB_HOST="${GITLAB_HOST:-gitlab-gitlab.apps.<YOUR_CLUSTER_DOMAIN>}"
QUAY_HOST="${QUAY_HOST:-quay.apps.<YOUR_CLUSTER_DOMAIN>}"

need_oc() {
  command -v oc >/dev/null || { echo "oc not found" >&2; exit 1; }
  oc whoami >/dev/null || { echo "oc not logged in" >&2; exit 1; }
}

main() {
  need_oc
  oc get ns "$NS" >/dev/null

  oc -n "$NS" create sa pipeline --dry-run=client -o yaml | oc apply -f -
  # buildah needs pipelines SCC; git push uses ordinary network
  oc adm policy add-scc-to-user pipelines-scc -z pipeline -n "$NS" || \
    oc adm policy add-scc-to-user anyuid -z pipeline -n "$NS"
  oc adm policy add-role-to-user edit -z pipeline -n "$NS"

  GITLAB_TOKEN="${GITLAB_TOKEN:-}"
  if [[ -z "$GITLAB_TOKEN" ]]; then
    GITLAB_TOKEN="$(oc -n gitlab get secret root-user-personal-token -o jsonpath='{.data.token}' | base64 -d)"
  fi

  # git-clone / git push basic-auth workspace
  oc -n "$NS" create secret generic gitlab-basic-auth \
    --from-literal=.gitconfig=$'[credential]\n\thelper = store\n' \
    --from-literal=.git-credentials="https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}" \
    --dry-run=client -o yaml | oc apply -f -
  oc -n "$NS" label secret gitlab-basic-auth app.kubernetes.io/part-of=fx-rate-demo --overwrite

  # Quay robot for buildah push
  QUAY_TOKEN="${QUAY_TOKEN:-}"
  if [[ -z "$QUAY_TOKEN" ]]; then
    QADMIN="$(oc -n quay-registry get secret quay-admin-token -o jsonpath='{.data.token}' | base64 -d)"
    QUAY_TOKEN="$(curl -sk -H "Authorization: Bearer ${QADMIN}" \
      "https://${QUAY_HOST}/api/v1/organization/fxrate/robots/builder" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')"
  fi
  oc -n "$NS" create secret docker-registry quay-push-secret \
    --docker-server="${QUAY_HOST}" \
    --docker-username="fxrate+builder" \
    --docker-password="${QUAY_TOKEN}" \
    --dry-run=client -o yaml | oc apply -f -
  oc -n "$NS" label secret quay-push-secret app.kubernetes.io/part-of=fx-rate-demo --overwrite

  # RHACS API token for roxctl image scan (AC-2.5). Generate in Central UI or API;
  # do not commit the token. Role: Continuous Integration (or Analyst).
  if [[ -n "${ACS_API_TOKEN:-}" ]]; then
    oc -n "$NS" create secret generic acs-api-token \
      --from-literal=token="${ACS_API_TOKEN}" \
      --dry-run=client -o yaml | oc apply -f -
    oc -n "$NS" label secret acs-api-token app.kubernetes.io/part-of=fx-rate-demo --overwrite
    echo "acs-api-token created/updated from ACS_API_TOKEN"
  elif oc -n "$NS" get secret acs-api-token >/dev/null 2>&1; then
    echo "acs-api-token already present"
  else
    echo "WARNING: acs-api-token missing. Create with:" >&2
    echo "  ACS_API_TOKEN=... bash cluster/tekton/setup-secrets.sh" >&2
    echo "  # or: oc -n ${NS} create secret generic acs-api-token --from-literal=token=..." >&2
  fi

  # Cosign signing key for sign-sbom task (same key as Tekton Chains signing-secrets).
  # Never commit cosign.key / password — copy from openshift-pipelines or generate once.
  if oc -n openshift-pipelines get secret signing-secrets >/dev/null 2>&1; then
    oc -n openshift-pipelines get secret signing-secrets -o json \
      | python3 -c '
import json,sys,base64
d=json.load(sys.stdin)["data"]
for k in ("cosign.key","cosign.password","cosign.pub"):
    if k not in d:
        sys.exit(f"signing-secrets missing {k}")
open("/tmp/cosign.key","wb").write(base64.b64decode(d["cosign.key"]))
open("/tmp/cosign.password","wb").write(base64.b64decode(d["cosign.password"]))
open("/tmp/cosign.pub","wb").write(base64.b64decode(d["cosign.pub"]))
print("extracted cosign materials from openshift-pipelines/signing-secrets")
'
    oc -n "$NS" create secret generic cosign-signing \
      --from-file=cosign.key=/tmp/cosign.key \
      --from-file=cosign.password=/tmp/cosign.password \
      --from-file=cosign.pub=/tmp/cosign.pub \
      --dry-run=client -o yaml | oc apply -f -
    oc -n "$NS" label secret cosign-signing app.kubernetes.io/part-of=fx-rate-demo --overwrite
    rm -f /tmp/cosign.key /tmp/cosign.password /tmp/cosign.pub
    echo "cosign-signing secret ready (from Chains signing-secrets)"
  elif oc -n "$NS" get secret cosign-signing >/dev/null 2>&1; then
    echo "cosign-signing already present"
  else
    echo "WARNING: cosign-signing missing and openshift-pipelines/signing-secrets not found" >&2
  fi

  echo "Secrets ready in ${NS}: gitlab-basic-auth, quay-push-secret, acs-api-token?, cosign-signing? (SA pipeline)"
}

main "$@"
