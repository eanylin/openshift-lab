#!/usr/bin/env bash
# Create ACS Cosign signature integration + prod policy (Image Signature Verified By).
# Pattern mirrors the default "Red Hat images must be signed…" policy on reference
# (pzp56): signature integration + policy field "Image Signature Verified By".
# Ours points at cluster/policies/cosign.pub and scopes fxrate-prod only.
#
# Prereq: oc logged in; Central reachable; Quay holds .sig for Act 3b
# (verified via Quay API). ACS must pull those .sig tags during scan.
#
# Usage:
#   ACS_ENFORCE=0 ./cluster/policies/acs-enable-signature-enforce.sh   # inform (default)
#   ACS_ENFORCE=1 ./cluster/policies/acs-enable-signature-enforce.sh   # deploy enforce
#   DRY_RUN=1 ...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PUB="${COSIGN_PUB:-$ROOT/cluster/policies/cosign.pub}"
CENTRAL_HOST="${ACS_CENTRAL_HOST:-central-rhacs-operator.apps.<YOUR_CLUSTER_DOMAIN>}"
CENTRAL="https://${CENTRAL_HOST}"
REGISTRY="${FXRATE_REGISTRY:-quay.apps.<YOUR_CLUSTER_DOMAIN>}"
REMOTE_REPO="${FXRATE_REMOTE:-fxrate/fx-rate-service}"
NS_SCOPE="${ACS_SIG_NAMESPACE:-fxrate-prod}"
INTEGRATION_NAME="${ACS_SIG_INTEGRATION_NAME:-fxrate-ci Chains cosign}"
POLICY_NAME="${ACS_SIG_POLICY_NAME:-fxrate images must be signed by demo cosign key}"
ACS_ENFORCE="${ACS_ENFORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ -f "$PUB" ]] || die "missing $PUB"
command -v oc >/dev/null || die "oc not found"
command -v python3 >/dev/null || die "python3 not found"

PASS="${ACS_ADMIN_PASSWORD:-}"
if [[ -z "$PASS" ]]; then
  PASS="$(oc -n rhacs-operator get secret central-htpasswd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
fi
[[ -n "$PASS" ]] || die "set ACS_ADMIN_PASSWORD or ensure rhacs-operator/central-htpasswd exists"

AUTH="admin:${PASS}"

curl_acs() {
  local method="$1"; shift
  local path="$1"; shift
  if [[ "$DRY_RUN" == "1" && "$method" != "GET" ]]; then
    log "DRY_RUN: $method $path"
    return 0
  fi
  curl -sk -u "$AUTH" -X "$method" "$CENTRAL$path" \
    -H 'Content-Type: application/json' "$@"
}

EXISTING_ID="$(curl -sk -u "$AUTH" "$CENTRAL/v1/signatureintegrations" | python3 -c '
import json,sys
name=sys.argv[1]
for i in json.load(sys.stdin).get("integrations",[]):
  if i.get("name")==name:
    print(i["id"]); break
' "$INTEGRATION_NAME")"

PEM="$(cat "$PUB")"
BODY="$(python3 - <<PY
import json
pem = """${PEM}"""
if not pem.endswith("\n"):
    pem += "\n"
payload = {
  "name": "${INTEGRATION_NAME}",
  "cosign": {
    "publicKeys": [{
      "name": "fxrate-ci pipeline cosign",
      "publicKeyPemEnc": pem,
    }]
  },
  "cosignCertificates": [],
  "transparencyLog": {
    "enabled": False,
    "url": "",
    "validateOffline": False,
    "publicKeyPemEnc": "",
  },
}
eid = "${EXISTING_ID}".strip()
if eid:
    payload["id"] = eid
print(json.dumps(payload))
PY
)"

if [[ -n "$EXISTING_ID" ]]; then
  log "updating signature integration $EXISTING_ID"
  if [[ "$DRY_RUN" != "1" ]]; then
    curl_acs PUT "/v1/signatureintegrations/$EXISTING_ID" -d "$BODY" -o /tmp/acs-sig-out.json
  fi
  SIG_ID="$EXISTING_ID"
else
  log "creating signature integration"
  if [[ "$DRY_RUN" == "1" ]]; then
    SIG_ID="dry-run-integration"
  else
    curl_acs POST "/v1/signatureintegrations" -d "$BODY" -o /tmp/acs-sig-out.json
    SIG_ID="$(python3 -c 'import json; print(json.load(open("/tmp/acs-sig-out.json"))["id"])')"
  fi
fi
log "signature integration id=$SIG_ID"

POLICY_JSON="$(python3 - <<PY
import json
enforce = "${ACS_ENFORCE}" == "1"
pol = {
  "name": "${POLICY_NAME}",
  "description": "Alert when fx-rate Quay images in prod are not verified by the demo Chains/cosign public key.",
  "rationale": "Act 4 supply-chain guardrail: only Trusted Pipeline-signed images may run in fxrate-prod.",
  "remediation": "Rebuild/sign via the demo pipeline (cosign-sign-sbom) or promote an already-signed digest.",
  "disabled": False,
  "categories": ["Supply Chain Security"],
  "lifecycleStages": ["DEPLOY"],
  "eventSource": "NOT_APPLICABLE",
  "exclusions": [],
  "scope": [{"cluster": "", "namespace": "${NS_SCOPE}", "label": None}],
  "severity": "HIGH_SEVERITY",
  "enforcementActions": [
    "FAIL_DEPLOYMENT_CREATE_ENFORCEMENT",
    "FAIL_DEPLOYMENT_UPDATE_ENFORCEMENT",
    "SCALE_TO_ZERO_ENFORCEMENT",
  ] if enforce else [],
  "notifiers": [],
  "policyVersion": "1.1",
  "policySections": [{
    "sectionName": "fx-rate Quay images must verify against demo cosign key",
    "policyGroups": [
      {
        "fieldName": "Image Registry",
        "booleanOperator": "OR",
        "negate": False,
        "values": [{"value": "${REGISTRY}"}],
      },
      {
        "fieldName": "Image Remote",
        "booleanOperator": "OR",
        "negate": False,
        "values": [{"value": "${REMOTE_REPO}"}],
      },
      {
        "fieldName": "Image Signature Verified By",
        "booleanOperator": "OR",
        "negate": False,
        "values": [{"value": "${SIG_ID}"}],
      },
    ],
  }],
}
print(json.dumps(pol))
PY
)"

EXISTING_POLICY_ID="$(curl -sk -u "$AUTH" "$CENTRAL/v1/policies" | python3 -c '
import json,sys
name=sys.argv[1]
for p in json.load(sys.stdin).get("policies",[]):
  if p.get("name")==name:
    print(p["id"]); break
' "$POLICY_NAME")"

if [[ -n "$EXISTING_POLICY_ID" ]]; then
  log "updating policy $EXISTING_POLICY_ID (enforce=$ACS_ENFORCE)"
  POLICY_JSON="$(python3 -c 'import json,sys; p=json.load(sys.stdin); p["id"]=sys.argv[1]; print(json.dumps(p))' "$EXISTING_POLICY_ID" <<<"$POLICY_JSON")"
  curl_acs PUT "/v1/policies/$EXISTING_POLICY_ID" -d "$POLICY_JSON" -o /tmp/acs-pol-out.json
else
  log "creating policy (enforce=$ACS_ENFORCE)"
  curl_acs POST "/v1/policies" -d "$POLICY_JSON" -o /tmp/acs-pol-out.json
fi

if [[ "$DRY_RUN" != "1" ]]; then
  python3 - <<'PY'
import json
p=json.load(open("/tmp/acs-pol-out.json"))
print("policy id=", p.get("id") or p)
print("enforcement=", p.get("enforcementActions"))
print("scope=", p.get("scope"))
PY
fi

DIGEST="${FXRATE_ACT3B_DIGEST:-sha256:6e23506088cc986c047f935e4b84f62880282e593c3aef3d5b9c8462d9a38ea6}"
log "requesting re-scan of $DIGEST"
if [[ "$DRY_RUN" != "1" ]]; then
  curl -sk -u "$AUTH" -X POST "$CENTRAL/v1/images/${DIGEST}/scan" \
    -H 'Content-Type: application/json' \
    -d '{"force":true}' -o /tmp/acs-scan.json -w 'scan_http=%{http_code}\n' || true
  sleep 5
  curl -sk -u "$AUTH" "$CENTRAL/v1/images/${DIGEST}" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("signature=", d.get("signature"))
print("signatureVerificationData=", d.get("signatureVerificationData"))
' || true
fi

if [[ "$ACS_ENFORCE" == "1" ]]; then
  log "enforce enabled — if creates still slip through:"
  log "  oc -n rhacs-operator rollout restart deploy/sensor deploy/admission-control"
fi

log "done."
if [[ "$ACS_ENFORCE" != "1" ]]; then
  log "Policy is INFORM only. Re-run with ACS_ENFORCE=1 after signatureVerificationData is populated."
fi
