#!/usr/bin/env bash
# Restore the resting demo state: Act 3b on fxrate-dev + fxrate-prod.
# Inverse of reset-to-act0.sh.
#
# Usage:
#   RESET_CONFIRM=yes make restore-act3b
#   RESET_CONFIRM=yes DRY_RUN=1 make restore-act3b

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIGESTS="${ROOT}/fx-rate-service/digests.env"
DRY_RUN="${DRY_RUN:-0}"
SKIP_PUSH="${SKIP_PUSH:-0}"
FORCE="${FORCE:-0}"
DEV_NS="${FXRATE_DEV_NS:-fxrate-dev}"
PROD_NS="${FXRATE_PROD_NS:-fxrate-prod}"
ARGO_NS="${ARGO_NS:-openshift-gitops}"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ "${RESET_CONFIRM:-}" == "yes" ]] || die "refusing to run without RESET_CONFIRM=yes"
[[ -f "$DIGESTS" ]] || die "missing $DIGESTS"
# shellcheck disable=SC1090
source "$DIGESTS"

ACT3B_REF="${FXRATE_ACT3B_REF:-}"
ACT3B_DIGEST="${FXRATE_ACT3B_DIGEST:-}"
[[ -n "$ACT3B_REF" && -n "$ACT3B_DIGEST" ]] || die "FXRATE_ACT3B_REF / FXRATE_ACT3B_DIGEST unset"

need_oc() {
  command -v oc >/dev/null || die "oc not found"
  oc whoami >/dev/null || die "oc not logged in"
}

pin_gitops_act3b() {
  local deploy="${ROOT}/fx-rate-gitops/base/deployment.yaml"
  local dev="${ROOT}/fx-rate-gitops/overlays/dev/kustomization.yaml"
  local prod="${ROOT}/fx-rate-gitops/overlays/prod/kustomization.yaml"
  local repo="${FXRATE_IMAGE_REPO}"

  # Keep base as overlay-pin stub if present; overlays own digests.
  if [[ -f "$deploy" ]] && grep -q 'overlay-pin' "$deploy" 2>/dev/null; then
    :
  else
    log "note: ensure base deployment uses ${repo}:overlay-pin"
  fi

  cat >"$dev" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${DEV_NS}
resources:
  - ../../base
labels:
  - pairs:
      environment: dev
      demo.fxrate.act: "3b"
    includeSelectors: false
commonAnnotations:
  demo.fxrate.image: 3.0.0-act3b
images:
  - name: ${repo}
    digest: ${ACT3B_DIGEST}
EOF

  cat >"$prod" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${PROD_NS}
resources:
  - ../../base
labels:
  - pairs:
      environment: prod
      demo.fxrate.act: "3b"
    includeSelectors: false
commonAnnotations:
  demo.fxrate.image: 3.0.0-act3b
# Prod pin moves via promote MR (open-prod-promote-mr), not CI push to main.
images:
  - name: ${repo}
    digest: ${ACT3B_DIGEST}
EOF

  log "GitOps files updated for Act 3b (dev+prod=${ACT3B_DIGEST})"
}

commit_and_push() {
  command -v git >/dev/null || die "git not found"
  cd "$ROOT"
  local other
  other="$(git status --porcelain --untracked-files=no | grep -v 'fx-rate-gitops/' || true)"
  if [[ -n "$other" && "$FORCE" != "1" ]]; then
    die "working tree has non-gitops changes; commit/stash them or FORCE=1"$'\n'"$other"
  fi

  git add fx-rate-gitops/base/deployment.yaml \
         fx-rate-gitops/overlays/dev/kustomization.yaml \
         fx-rate-gitops/overlays/prod/kustomization.yaml

  if git diff --cached --quiet; then
    log "GitOps already at Act 3b pin"
  else
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY_RUN: would commit Act 3b restore"
      git diff --cached --stat
      git reset HEAD >/dev/null
      return 0
    fi
    git commit -m "demo: restore GitOps to Act 3b resting state [skip ci]"
  fi

  if [[ "$SKIP_PUSH" == "1" ]]; then
    log "SKIP_PUSH=1 — not pushing"
    return 0
  fi
  [[ "$DRY_RUN" == "1" ]] && { log "DRY_RUN: would push"; return 0; }
  git push origin HEAD:main
  log "pushed $(git rev-parse --short HEAD) → origin/main"
}

argo_sync() {
  local app="$1"
  [[ "$DRY_RUN" == "1" || "$SKIP_PUSH" == "1" ]] && { log "skip argo sync $app"; return 0; }
  oc -n "$ARGO_NS" patch application "$app" --type merge -p \
    "{\"operation\":{\"initiatedBy\":{\"username\":\"make-restore\"},\"sync\":{\"revision\":\"HEAD\"}}}"
}

wait_both() {
  [[ "$DRY_RUN" == "1" || "$SKIP_PUSH" == "1" ]] && return 0
  local i syncd syncp img
  for i in $(seq 1 36); do
    syncd="$(oc -n "$ARGO_NS" get application fx-rate-dev -o jsonpath='{.status.sync.status}')"
    syncp="$(oc -n "$ARGO_NS" get application fx-rate-prod -o jsonpath='{.status.sync.status}')"
    img="$(oc -n "$DEV_NS" get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    echo "  t=${i} dev=${syncd} prod=${syncp}"
    if [[ "$syncd" == "Synced" && "$syncp" == "Synced" && "$img" == *"${ACT3B_DIGEST#sha256:}"* ]]; then
      break
    fi
    sleep 5
  done
  oc -n "$DEV_NS" rollout status deploy/fx-rate-service --timeout=180s || true
  oc -n "$PROD_NS" rollout status deploy/fx-rate-service --timeout=180s || true
  log "dev=$(oc -n "$DEV_NS" get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}')"
  log "prod=$(oc -n "$PROD_NS" get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo missing)"
}

main() {
  need_oc
  log "restore → Act 3b ${ACT3B_REF}"
  pin_gitops_act3b
  if [[ "$DRY_RUN" == "1" ]]; then
    commit_and_push
    argo_sync fx-rate-dev
    argo_sync fx-rate-prod
    git -C "$ROOT" checkout -- \
      fx-rate-gitops/base/deployment.yaml \
      fx-rate-gitops/overlays/dev/kustomization.yaml \
      fx-rate-gitops/overlays/prod/kustomization.yaml 2>/dev/null || true
    log "DRY_RUN complete (GitOps files restored)."
    return 0
  fi
  commit_and_push
  argo_sync fx-rate-dev
  argo_sync fx-rate-prod
  wait_both
  log "Act 3b resting state restored."
}

main "$@"
