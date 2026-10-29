#!/usr/bin/env bash
# Fallback: deploy Act 0 to fxrate-dev via kustomize.
# Preferred path: push GitLab main → Argo app fx-rate-dev (auto-sync).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIGESTS="${ROOT}/fx-rate-service/digests.env"
# shellcheck disable=SC1090
source "$DIGESTS"

NS="${FXRATE_DEV_NS:-fxrate-dev}"
IMG="${FXRATE_IMAGE_REPO}@${FXRATE_LEGACY_DIGEST:-${FXRATE_IMAGE_DIGEST}}"

need_oc() {
  command -v oc >/dev/null || { echo "oc not found" >&2; exit 1; }
  oc whoami >/dev/null || { echo "oc not logged in" >&2; exit 1; }
}

main() {
  need_oc
  if [[ "$IMG" == *"REPLACE_ME"* ]] || [[ -z "${FXRATE_LEGACY_DIGEST:-${FXRATE_IMAGE_DIGEST:-}}" ]]; then
    echo "Set FXRATE_LEGACY_DIGEST (or FXRATE_IMAGE_DIGEST) in digests.env first" >&2
    exit 1
  fi

  echo "Deploying Act 0 image: $IMG"
  oc -n "$NS" apply -k "${ROOT}/fx-rate-gitops/overlays/dev"
  oc -n "$NS" set image deploy/fx-rate-service "fx-rate-service=${IMG}"
  oc -n "$NS" rollout status deploy/fx-rate-service --timeout=5m
  oc -n "$NS" get route fx-rate-service -o jsonpath='{.spec.host}{"\n"}'
}

main "$@"
