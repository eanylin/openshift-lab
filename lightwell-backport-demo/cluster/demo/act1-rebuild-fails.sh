#!/usr/bin/env bash
# Act 1 fallback reproduction (spec §5.2, AC-1.1 / AC-1.2 / AC-1.3).
# Shows: R0 top-level pins resolve Werkzeug 3.x → import flask fails with url_quote.
# Also shows Flask 2.3 DeprecationWarnings from the Act 0 (L0) image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/fx-rate-service/digests.env"

NEXUS_INDEX="${NEXUS_PYPI_SIMPLE:?}"
LEGACY_BASE="${LEGACY_PYTHON_REF:?}"
LEGACY_APP="${FXRATE_LEGACY_REF:?}"
OUT_DIR="${ACT1_OUT_DIR:-/tmp/fxrate-act1}"
mkdir -p "$OUT_DIR"

echo "==> Act 1: install R0 (top-level pins only) via Nexus on ${LEGACY_BASE}"
# Inline R0 pins (same as legacy/requirements.txt) to avoid volume/SELinux friction.
podman run --rm \
  -e PIP_INDEX_URL="${NEXUS_INDEX}" \
  "${LEGACY_BASE}" \
  bash -lc '
set -euo pipefail
python -V
printf "%s\n" "flask==2.2.2" "requests==2.28.2" "gunicorn==20.1.0" > /tmp/requirements.txt
pip install -q -r /tmp/requirements.txt
python <<PY
from importlib import metadata as m
print("--- resolved versions ---")
for name in ("flask", "werkzeug", "requests", "urllib3"):
    print(f"{name} {m.version(name)}")
print("--- import flask (expect ImportError: url_quote) ---")
try:
    import flask  # noqa: F401
    print("UNEXPECTED: import flask succeeded")
except Exception as e:
    print(f"{type(e).__name__}: {e}")
PY
' | tee "${OUT_DIR}/r0-install.log"

echo
echo "==> Act 1: DeprecationWarnings from Act 0 L0 image (AC-1.3)"
podman run --rm --entrypoint python \
  -e PYTHONWARNINGS=default \
  "${LEGACY_APP}" \
  -W default -c "import fxrate" \
  2>&1 | tee "${OUT_DIR}/l0-deprecations.log" || true

echo
echo "Logs written under ${OUT_DIR}/"
echo "Talk track: The resolver said yes. The app said no. Pinning Flask did not pin Werkzeug."
