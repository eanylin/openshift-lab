#!/usr/bin/env bash
# Configure Nexus CE: anonymous browse + pypi-proxy-pypi (and optional rhtl stub).
set -euo pipefail

NS="${NEXUS_NS:-nexus}"
ROUTE_HOST="${NEXUS_HOST:-nexus.apps.<YOUR_CLUSTER_DOMAIN>}"
BASE_URL="https://${ROUTE_HOST}"
SVC_URL="http://nexus.${NS}.svc:8081"

need_oc() {
  command -v oc >/dev/null || { echo "oc not found" >&2; exit 1; }
  oc whoami >/dev/null || { echo "oc not logged in" >&2; exit 1; }
}

wait_ready() {
  echo "Waiting for Nexus deployment..."
  oc -n "$NS" rollout status deployment/nexus --timeout=10m
  echo "Waiting for /service/rest/v1/status ..."
  local i
  for i in $(seq 1 60); do
    if oc -n "$NS" exec deploy/nexus -- curl -sf "http://127.0.0.1:8081/service/rest/v1/status" >/dev/null 2>&1; then
      echo "Nexus API is up"
      return 0
    fi
    sleep 10
  done
  echo "Nexus did not become ready in time" >&2
  exit 1
}

admin_password() {
  # Prefer generated password file; fall back to classic default for fresh installs that still use it.
  local pw
  pw="$(oc -n "$NS" exec deploy/nexus -- cat /nexus-data/admin.password 2>/dev/null || true)"
  if [[ -n "${pw}" ]]; then
    printf '%s' "$pw"
    return 0
  fi
  printf 'admin123'
}

create_pypi_proxy() {
  local name="$1"
  local remote="$2"
  local pw="$3"
  local payload
  payload=$(cat <<EOF
{
  "name": "${name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "${remote}",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  }
}
EOF
)

  local code
  code=$(oc -n "$NS" exec deploy/nexus -- \
    curl -s -o /tmp/nexus-create-out -w '%{http_code}' \
    -u "admin:${pw}" \
    -H 'Content-Type: application/json' \
    -X POST "http://127.0.0.1:8081/service/rest/v1/repositories/pypi/proxy" \
    -d "${payload}" || true)

  if [[ "$code" == "201" ]]; then
    echo "Created repository ${name}"
  elif [[ "$code" == "400" ]] && oc -n "$NS" exec deploy/nexus -- curl -sf -u "admin:${pw}" \
      "http://127.0.0.1:8081/service/rest/v1/repositories/${name}" >/dev/null 2>&1; then
    echo "Repository ${name} already exists"
  else
    echo "Failed creating ${name} (HTTP ${code})" >&2
    oc -n "$NS" exec deploy/nexus -- cat /tmp/nexus-create-out 2>/dev/null || true
    exit 1
  fi
}

create_raw_proxy() {
  local name="$1"
  local remote="$2"
  local pw="$3"
  local payload
  payload=$(cat <<EOF
{
  "name": "${name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": false
  },
  "proxy": {
    "remoteUrl": "${remote}",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  },
  "raw": {
    "contentDisposition": "ATTACHMENT"
  }
}
EOF
)
  local code
  code=$(oc -n "$NS" exec deploy/nexus -- \
    curl -s -o /tmp/nexus-create-out -w '%{http_code}' \
    -u "admin:${pw}" \
    -H 'Content-Type: application/json' \
    -X POST "http://127.0.0.1:8081/service/rest/v1/repositories/raw/proxy" \
    -d "${payload}" || true)
  if [[ "$code" == "201" ]]; then
    echo "Created repository ${name}"
  elif [[ "$code" == "400" ]] && oc -n "$NS" exec deploy/nexus -- curl -sf -u "admin:${pw}" \
      "http://127.0.0.1:8081/service/rest/v1/repositories/${name}" >/dev/null 2>&1; then
    echo "Repository ${name} already exists"
  else
    echo "Failed creating ${name} (HTTP ${code})" >&2
    oc -n "$NS" exec deploy/nexus -- cat /tmp/nexus-create-out 2>/dev/null || true
    return 1
  fi
}

enable_anonymous() {
  local pw="$1"
  oc -n "$NS" exec deploy/nexus -- \
    curl -sf -u "admin:${pw}" \
    -H 'Content-Type: application/json' \
    -X PUT "http://127.0.0.1:8081/service/rest/v1/security/anonymous" \
    -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' >/dev/null
  echo "Anonymous access enabled"
}

accept_eula() {
  local pw="$1"
  # CE blocks component download/upload until EULA is accepted (3.77+).
  oc -n "$NS" exec deploy/nexus -- \
    curl -sf -u "admin:${pw}" "http://127.0.0.1:8081/service/rest/v1/system/eula" > /tmp/nexus-eula.json
  python3 - <<'PY'
import json
with open("/tmp/nexus-eula.json", encoding="utf-8") as f:
    data = json.load(f)
if data.get("accepted"):
    print("Nexus CE EULA already accepted")
    raise SystemExit(0)
data["accepted"] = True
with open("/tmp/nexus-eula-accept.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
PY
  local pod
  pod="$(oc -n "$NS" get pod -l app.kubernetes.io/name=nexus -o jsonpath='{.items[0].metadata.name}')"
  oc -n "$NS" cp /tmp/nexus-eula-accept.json "${pod}:/tmp/nexus-eula-accept.json"
  oc -n "$NS" exec deploy/nexus -- \
    curl -sf -u "admin:${pw}" \
    -H 'Content-Type: application/json; charset=UTF-8' \
    -X POST "http://127.0.0.1:8081/service/rest/v1/system/eula" \
    --data-binary @/tmp/nexus-eula-accept.json >/dev/null
  echo "Nexus CE EULA accepted"
}

main() {
  need_oc
  wait_ready
  local pw
  pw="$(admin_password)"
  echo "Using admin password from Nexus data volume (len=${#pw})"
  enable_anonymous "$pw"
  accept_eula "$pw"
  create_pypi_proxy "pypi-proxy-pypi" "https://pypi.org/" "$pw"
  # Legacy stub (PyPI layout + /simple/ does not match TL). Prefer raw-proxy-rhtl for Act 3b.
  create_pypi_proxy "pypi-proxy-rhtl" "https://packages.redhat.com/trusted-libraries/python/" "$pw" || true
  create_raw_proxy "raw-proxy-rhtl" "https://packages.redhat.com/trusted-libraries/python/" "$pw" || true

  # Act 3b hosted T2 mirror (relative URLs) — populate after raw-proxy-rhtl works:
  #   bash cluster/nexus/hosted-rhtl/populate-hosted-rhtl.sh
  # Lightwell backport mock (hosted PyPI) — Act 0 pins + +rhlw-0001 (not TL upgrades):
  #   bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh
  # See cluster/docs/LIGHTWELL-MOCK.md
  # Hosted repos are NOT created by this script; they vanish if Nexus PVC/data is wiped.

  echo
  echo "Nexus route: ${BASE_URL}"
  echo "PyPI simple: ${BASE_URL}/repository/pypi-proxy-pypi/simple"
  echo "TL raw:      ${BASE_URL}/repository/raw-proxy-rhtl/   (populate source for hosted T2)"
  echo "T2 hosted:   ${BASE_URL}/repository/pypi-hosted-rhtl/simple/  (Act 3b pip --index-url)"
  echo "RHLW mock:   ${BASE_URL}/repository/pypi-hosted-rhlw/simple/  (after populate-mock-lightwell.sh)"
  echo "In-cluster:  ${SVC_URL}/repository/pypi-proxy-pypi/simple"
  echo
  echo "Smoke: curl ${BASE_URL}/repository/pypi-proxy-pypi/simple/flask/"
  echo "Smoke: curl ${BASE_URL}/repository/raw-proxy-rhtl/flask/"
}

main "$@"
