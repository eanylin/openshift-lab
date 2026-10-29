#!/usr/bin/env bash
# Create Nexus hosted PyPI pypi-hosted-rhlw and upload Lightwell-style mock wheels.
#
# Lab mock only — not Red Hat Lightwell Network content.
# Versions become <upstream>+rhlw-0001 (PEP 440 local; see LIGHTWELL-MOCK.md).
# Upstream pins are Act 0 (e.g. flask 2.2.2) — backport-in-place, not TL upgrades.
#
# Usage (bastion or laptop with oc + curl + python3):
#   bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh
#   RHLW_BUILD=0002 SOURCE_INDEX=... bash cluster/nexus/mock-lightwell/populate-mock-lightwell.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PKG_LIST="${PKG_LIST:-$(cd "$(dirname "$0")" && pwd)/packages.txt}"
REPACK_PY="$(cd "$(dirname "$0")" && pwd)/repack_rhlw_wheel.py"

NS="${NEXUS_NS:-nexus}"
NEXUS_HOST="${NEXUS_HOST:-nexus.apps.<YOUR_CLUSTER_DOMAIN>}"
NEXUS_URL="${NEXUS_URL:-https://${NEXUS_HOST}}"
REPO_NAME="${RHLW_REPO:-pypi-hosted-rhlw}"
# Product display is .rhlw-00001; lab PEP 440 local segment is +rhlw-0001.
RHLW_BUILD="${RHLW_BUILD:-0001}"
# Act 0 wheels live on public PyPI (via Nexus proxy) — not TL raw-proxy-rhtl.
SOURCE_INDEX="${SOURCE_INDEX:-${NEXUS_URL}/repository/pypi-proxy-pypi/simple}"
WORK="${WORK_DIR:-/tmp/mock-lightwell-$$}"
UPLOAD="${UPLOAD:-1}"
PURGE_OLD="${PURGE_OLD:-1}"

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
  # pip download against index (TL raw has no /simple/ suffix)
  python3 -m pip download \
    --no-deps \
    --only-binary=:all: \
    --dest "$dest" \
    --index-url "${index}" \
    --trusted-host "${NEXUS_HOST}" \
    "${name}==${ver}" \
    >/dev/null
}

upload_wheel() {
  local pw="$1" wheel="$2"
  local code
  # Prefer in-cluster upload via oc exec + curl file (avoids route auth quirks).
  local pod
  pod="$(oc -n "$NS" get pod -l app.kubernetes.io/name=nexus -o jsonpath='{.items[0].metadata.name}')"
  local base
  base="$(basename "$wheel")"
  oc -n "$NS" cp "$wheel" "${pod}:/tmp/${base}"
  code=$(oc -n "$NS" exec deploy/nexus -- \
    curl -s -o /tmp/nexus-upload-out -w '%{http_code}' \
    -u "admin:${pw}" \
    -F "pypi.asset=@/tmp/${base}" \
    "http://127.0.0.1:8081/service/rest/v1/components?repository=${REPO_NAME}" || true)
  oc -n "$NS" exec deploy/nexus -- rm -f "/tmp/${base}" >/dev/null 2>&1 || true
  if [[ "$code" != "204" && "$code" != "200" ]]; then
    echo "Upload failed for ${base} (HTTP ${code})" >&2
    oc -n "$NS" exec deploy/nexus -- cat /tmp/nexus-upload-out 2>/dev/null || true
    return 1
  fi
  echo "Uploaded ${base}"
}

# Drop prior mock components so old 3.1.3+rhlw wheels cannot confuse demos.
purge_repo_components() {
  local pw="$1"
  local cont="" page ids id
  echo "Purging existing components in ${REPO_NAME}..."
  while true; do
    if [[ -n "$cont" ]]; then
      page=$(oc -n "$NS" exec deploy/nexus -- \
        curl -sf -u "admin:${pw}" \
        "http://127.0.0.1:8081/service/rest/v1/components?repository=${REPO_NAME}&continuationToken=${cont}" || true)
    else
      page=$(oc -n "$NS" exec deploy/nexus -- \
        curl -sf -u "admin:${pw}" \
        "http://127.0.0.1:8081/service/rest/v1/components?repository=${REPO_NAME}" || true)
    fi
    [[ -z "$page" ]] && break
    ids=$(printf '%s' "$page" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(i["id"] for i in d.get("items",[])))' 2>/dev/null || true)
    while IFS= read -r id || [[ -n "$id" ]]; do
      [[ -z "$id" ]] && continue
      oc -n "$NS" exec deploy/nexus -- \
        curl -sf -u "admin:${pw}" -X DELETE \
        "http://127.0.0.1:8081/service/rest/v1/components/${id}" >/dev/null \
        && echo "  deleted ${id}" || echo "  WARN: delete ${id} failed" >&2
    done <<< "$ids"
    cont=$(printf '%s' "$page" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("continuationToken") or "")' 2>/dev/null || true)
    [[ -z "$cont" ]] && break
  done
}

main() {
  echo "Nexus:     ${NEXUS_URL}"
  echo "Repo:      ${REPO_NAME}"
  echo "Source:    ${SOURCE_INDEX}"
  echo "RHLW:      +rhlw-${RHLW_BUILD}"
  echo "Packages:  ${PKG_LIST}"
  echo

  local pw
  pw="$(admin_password)"
  create_hosted "$pw"
  if [[ "${PURGE_OLD}" == "1" ]]; then
    purge_repo_components "$pw"
  fi

  mkdir -p "${WORK}/dl" "${WORK}/out"
  # Ensure pip available
  python3 -m pip --version >/dev/null

  local line name ver wheel outw backport
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Lines starting with ">" are backported (repacked +rhlw-XXXX).
    # All others are passthrough (uploaded as-is).
    backport=0
    if [[ "$line" == ">"* ]]; then
      backport=1
      line="${line#>}"
    fi
    name="${line%%==*}"
    ver="${line#*==}"
    name="$(echo "$name" | tr -d '[:space:]')"
    ver="$(echo "$ver" | tr -d '[:space:]')"
    rm -f "${WORK}/dl"/*.whl
    if ! download_wheel "$name" "$ver" "${WORK}/dl" "${SOURCE_INDEX}"; then
      echo "WARN: download failed for ${name}==${ver} from primary index; trying PyPI proxy" >&2
      if ! download_wheel "$name" "$ver" "${WORK}/dl" \
          "${NEXUS_URL}/repository/pypi-proxy-pypi/simple"; then
        echo "FAIL: ${name}==${ver}" >&2
        continue
      fi
    fi
    wheel="$(ls -1 "${WORK}/dl"/*.whl | head -1)"
    if [[ "$backport" == "1" ]]; then
      echo "--- ${name}==${ver} → ${ver}+rhlw-${RHLW_BUILD}  [BACKPORT]"
      outw="$(python3 "${REPACK_PY}" "$wheel" -o "${WORK}/out" --rhlw-build "${RHLW_BUILD}")"
    else
      echo "--- ${name}==${ver}  [passthrough]"
      outw="$wheel"
    fi
    if [[ "${UPLOAD}" == "1" ]]; then
      upload_wheel "$pw" "$outw"
    else
      echo "Built (no upload): ${outw}"
    fi
  done < "${PKG_LIST}"

  echo
  echo "Simple index: ${NEXUS_URL}/repository/${REPO_NAME}/simple/"
  echo "Smoke:"
  echo "  curl -sk ${NEXUS_URL}/repository/${REPO_NAME}/simple/flask/"
  echo "  pip install --index-url ${NEXUS_URL}/repository/${REPO_NAME}/simple --no-deps 'urllib3==1.26.14+rhlw-${RHLW_BUILD}'"
  echo "  pip show urllib3  # expect Version: 1.26.14+rhlw-${RHLW_BUILD}"
}

main "$@"
