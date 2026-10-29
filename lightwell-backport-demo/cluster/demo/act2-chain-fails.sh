#!/usr/bin/env bash
# Act 2 stage helpers (spec §5.3 AC-2.1 / AC-2.2): why "just patch" needs a new Python.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/fx-rate-service/digests.env"

NEXUS_INDEX="${NEXUS_PYPI_SIMPLE:?}"
PY39="${LEGACY_PYTHON_REF:?}"
PY312="${ACT2_PYTHON_REF:?}"
OUT_DIR="${ACT2_OUT_DIR:-/tmp/fxrate-act2}"
mkdir -p "$OUT_DIR"

echo "==> AC-2.1: on Python 3.9, requests 2.33.0 / urllib3>=2.7.0 fail Requires-Python"
podman run --rm -e PIP_INDEX_URL="${NEXUS_INDEX}" "${PY39}" bash -lc '
set +e
python -V
echo "--- pip install --dry-run requests==2.33.0 ---"
pip install --dry-run --index-url "$PIP_INDEX_URL" "requests==2.33.0" 2>&1 | tail -20
echo "--- pip install --dry-run urllib3>=2.7.0 ---"
pip install --dry-run --index-url "$PIP_INDEX_URL" "urllib3>=2.7.0" 2>&1 | tail -20
' | tee "${OUT_DIR}/ac-2.1-py39.log"

echo
echo "==> AC-2.2: on Python 3.12, requests==2.28.2 + urllib3>=2.7.0 → ResolutionImpossible"
podman run --rm -e PIP_INDEX_URL="${NEXUS_INDEX}" "${PY312}" bash -lc '
set +e
python -V
echo "--- pip install --dry-run requests==2.28.2 urllib3>=2.7.0 ---"
pip install --dry-run --index-url "$PIP_INDEX_URL" "requests==2.28.2" "urllib3>=2.7.0" 2>&1 | tail -30
' | tee "${OUT_DIR}/ac-2.2-py312.log"

echo
echo "Logs under ${OUT_DIR}/"
echo "Talk track: To fix urllib3 we needed newer requests → newer Python → new base → Flask 3 code changes."
