#!/usr/bin/env bash
# AC-3b.1 — T1 hashed lock against Trusted Libraries-only index → hash mismatch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/fx-rate-service/digests.env"

TL_INDEX="${NEXUS_RHTL_SIMPLE:?}"
HOST="${NEXUS_TRUSTED_HOST:-nexus.apps.<YOUR_CLUSTER_DOMAIN>}"
IMG="${RHHI_BUILDER_REF:?}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
grep -vE '^(--index-url|--extra-index-url)' \
  "${ROOT}/fx-rate-service/requirements.txt" > "${WORKDIR}/reqs-t1.txt"

echo "Expect HASH MISMATCH installing T1 lock from ${TL_INDEX}"
set +e
podman run --rm --user 0 --network host \
  -v "${WORKDIR}:/work:z" --workdir /work --entrypoint /bin/bash "${IMG}" -lc "
  python3 -m venv /tmp/v && . /tmp/v/bin/activate
  pip install -q --upgrade pip
  pip install --index-url '${TL_INDEX}' --trusted-host '${HOST}' \
    --require-hashes --no-deps --only-binary=:all: -r reqs-t1.txt
"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "UNEXPECTED: T1 lock installed cleanly from TL (AC-3b.1 failed)" >&2
  exit 1
fi
echo "AC-3b.1 OK: pip refused T1 hashes against Trusted Libraries wheels (exit=${rc})"
