#!/usr/bin/env bash
# Mirror Act 3b Trusted Libraries T2 wheels into Nexus hosted PyPI.
#
# Why: raw-proxy-rhtl simple pages emit absolute packages.redhat.com URLs;
# pip in fxrate-ci then hits the CDN (EgressFirewall / flaky Akamai).
# Hosted PyPI serves relative URLs — CI stays on Nexus only.
#
# Wheels are uploaded unchanged so requirements-t2.txt hashes still match.
#
# Usage (bastion with oc + python3; needs CDN reach for the one-time fetch):
#   bash cluster/nexus/hosted-rhtl/populate-hosted-rhtl.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PKG_LIST="${PKG_LIST:-$(cd "$(dirname "$0")" && pwd)/packages.txt}"

NS="${NEXUS_NS:-nexus}"
NEXUS_HOST="${NEXUS_HOST:-nexus.apps.<YOUR_CLUSTER_DOMAIN>}"
NEXUS_URL="${NEXUS_URL:-https://${NEXUS_HOST}}"
REPO_NAME="${RHTL_REPO:-pypi-hosted-rhtl}"
# Fetch once via TL raw proxy (or override). Bastion/Nexus can reach upstream.
SOURCE_INDEX="${SOURCE_INDEX:-${NEXUS_URL}/repository/raw-proxy-rhtl/}"
WORK="${WORK_DIR:-/tmp/hosted-rhtl-$$}"
UPLOAD="${UPLOAD:-1}"
PIP_RETRIES="${PIP_RETRIES:-15}"
PIP_TIMEOUT="${PIP_TIMEOUT:-120}"

need() { command -v "$1" >/dev/null || { echo "need $1" >&2; exit 1; }; }
need oc
need curl
need python3

admin_password() {
  local pw
  pw="$(oc -n "$NS" exec deploy/nexus -- cat /nexus-data/admin.password 2>/dev/null || true)"
  if [[ -n "${pw}" ]]; then
    printf '%s' "$pw"
    return 0
  fi
  printf 'admin123'
}

create_hosted() {
  local pw="$1"
  local payload
  payload=$(cat <<EOF
{
  "name": "${REPO_NAME}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  },
  "component": {
    "proprietaryComponents": true
  }
}
EOF
)
  local code
  code=$(oc -n "$NS" exec deploy/nexus -- \
    curl -s -o /tmp/nexus-create-out -w '%{http_code}' \
    -u "admin:${pw}" \
    -H 'Content-Type: application/json' \
    -X POST "http://127.0.0.1:8081/service/rest/v1/repositories/pypi/hosted" \
    -d "${payload}" || true)
  if [[ "$code" == "201" ]]; then
    echo "Created hosted PyPI ${REPO_NAME}"
  elif [[ "$code" == "400" ]] && oc -n "$NS" exec deploy/nexus -- curl -sf -u "admin:${pw}" \
      "http://127.0.0.1:8081/service/rest/v1/repositories/${REPO_NAME}" >/dev/null 2>&1; then
    echo "Hosted repository ${REPO_NAME} already exists"
  else
    echo "Failed creating ${REPO_NAME} (HTTP ${code})" >&2
    oc -n "$NS" exec deploy/nexus -- cat /tmp/nexus-create-out 2>/dev/null || true
    exit 1
  fi
}

download_wheel() {
  local name="$1" ver="$2" dest="$3" index="$4"
  python3 -m pip download \
    --no-deps \
    --only-binary=:all: \
    --dest "$dest" \
    --index-url "${index}" \
    --trusted-host "${NEXUS_HOST}" \
    --retries "${PIP_RETRIES}" \
    --timeout "${PIP_TIMEOUT}" \
    "${name}==${ver}" \
    >/dev/null
}

upload_wheel() {
  local pw="$1" wheel="$2"
  local code pod base
  pod="$(oc -n "$NS" get pod -l app.kubernetes.io/name=nexus -o jsonpath='{.items[0].metadata.name}')"
  base="$(basename "$wheel")"
  oc -n "$NS" cp "$wheel" "${pod}:/tmp/${base}"
  code=$(oc -n "$NS" exec deploy/nexus -- \
    curl -s -o /tmp/nexus-upload-out -w '%{http_code}' \
    -u "admin:${pw}" \
    -F "pypi.asset=@/tmp/${base}" \
    "http://127.0.0.1:8081/service/rest/v1/components?repository=${REPO_NAME}" || true)
  oc -n "$NS" exec deploy/nexus -- rm -f "/tmp/${base}" >/dev/null 2>&1 || true
  if [[ "$code" != "204" && "$code" != "200" ]]; then
    # 400 often means component already present — treat as OK for re-runs.
    if [[ "$code" == "400" ]] && oc -n "$NS" exec deploy/nexus -- \
        grep -qiE 'already exists|Repository does not allow updating' /tmp/nexus-upload-out 2>/dev/null; then
      echo "Already present: ${base}"
      return 0
    fi
    echo "Upload failed for ${base} (HTTP ${code})" >&2
    oc -n "$NS" exec deploy/nexus -- cat /tmp/nexus-upload-out 2>/dev/null || true
    return 1
  fi
  echo "Uploaded ${base}"
}

main() {
  echo "Nexus:     ${NEXUS_URL}"
  echo "Repo:      ${REPO_NAME}"
  echo "Source:    ${SOURCE_INDEX}"
  echo "Packages:  ${PKG_LIST}"
  echo

  local pw
  pw="$(admin_password)"
  create_hosted "$pw"

  mkdir -p "${WORK}/dl"
  python3 -m pip --version >/dev/null

  local line name ver wheel fail=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    name="${line%%==*}"
    ver="${line#*==}"
    name="$(echo "$name" | tr -d '[:space:]')"
    ver="$(echo "$ver" | tr -d '[:space:]')"
    echo "--- ${name}==${ver}"
    rm -f "${WORK}/dl"/*.whl
    if ! download_wheel "$name" "$ver" "${WORK}/dl" "${SOURCE_INDEX}"; then
      echo "WARN: TL download failed for ${name}==${ver}; trying PyPI proxy (hashes may not match T2)" >&2
      if ! download_wheel "$name" "$ver" "${WORK}/dl" \
          "${NEXUS_URL}/repository/pypi-proxy-pypi/simple"; then
        echo "FAIL: ${name}==${ver}" >&2
        fail=1
        continue
      fi
    fi
    wheel="$(ls -1 "${WORK}/dl"/*.whl | head -1)"
    if [[ "${UPLOAD}" == "1" ]]; then
      upload_wheel "$pw" "$wheel" || fail=1
    else
      echo "Downloaded (no upload): ${wheel}"
    fi
  done < "${PKG_LIST}"

  echo
  echo "Simple index: ${NEXUS_URL}/repository/${REPO_NAME}/simple/"
  echo "Smoke:"
  echo "  curl -sk ${NEXUS_URL}/repository/${REPO_NAME}/simple/flask/"
  echo "  pip install --index-url ${NEXUS_URL}/repository/${REPO_NAME}/simple --no-deps flask==3.1.3"
  [[ "$fail" -eq 0 ]] || exit 1
}

main "$@"
