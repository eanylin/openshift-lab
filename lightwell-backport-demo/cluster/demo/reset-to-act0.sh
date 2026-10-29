#!/usr/bin/env bash
# Reset the demo lab to Act 0 (FR-040).
#
# What it does:
#   1. Pins fx-rate-gitops base image to FXRATE_LEGACY_* (OptB / 1.0.0-legacy)
#   2. Labels overlays/dev as Act 0; empties overlays/prod (so Argo prune clears prod)
#   3. Commits + pushes to origin main (unless SKIP_PUSH=1)
#   4. Syncs Argo fx-rate-dev; syncs fx-rate-prod with prune
#   5. Waits for /versions on dev to show flask 2.2.2
#
# Usage (repo root, oc logged in, digests.env present):
#   RESET_CONFIRM=yes make reset
#   RESET_CONFIRM=yes DRY_RUN=1 make reset
#   RESET_CONFIRM=yes SKIP_PUSH=1 make reset   # local GitOps edit + oc fallback only
#
# Companion: cluster/demo/restore-act3b.sh (make restore-act3b)

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

[[ -f "$DIGESTS" ]] || die "missing $DIGESTS — cp fx-rate-service/digests.env.example digests.env"
# shellcheck disable=SC1090
source "$DIGESTS"

LEGACY_REF="${FXRATE_LEGACY_REF:-}"
[[ -n "$LEGACY_REF" ]] || die "FXRATE_LEGACY_REF unset in digests.env"
LEGACY_DIGEST="${FXRATE_LEGACY_DIGEST:-}"
[[ -n "$LEGACY_DIGEST" ]] || die "FXRATE_LEGACY_DIGEST unset in digests.env"

need_oc() {
  command -v oc >/dev/null || die "oc not found"
  oc whoami >/dev/null || die "oc not logged in"
}

need_git() {
  command -v git >/dev/null || die "git not found"
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git checkout: $ROOT"
}

pin_gitops_act0() {
  local deploy="${ROOT}/fx-rate-gitops/base/deployment.yaml"
  local dev="${ROOT}/fx-rate-gitops/overlays/dev/kustomization.yaml"
  local prod="${ROOT}/fx-rate-gitops/overlays/prod/kustomization.yaml"
  local repo="${FXRATE_IMAGE_REPO}"

  # Base stays tag-only; overlays pin digests.
  cat >"$deploy" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fx-rate-service
  labels:
    app.kubernetes.io/name: fx-rate-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: fx-rate-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: fx-rate-service
    spec:
      containers:
        - name: fx-rate-service
          image: ${repo}:overlay-pin
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          env:
            - name: PYTHONWARNINGS
              value: default
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
---
apiVersion: v1
kind: Service
metadata:
  name: fx-rate-service
  labels:
    app.kubernetes.io/name: fx-rate-service
spec:
  selector:
    app.kubernetes.io/name: fx-rate-service
  ports:
    - name: http
      port: 8080
      targetPort: http
EOF

  cat >"$dev" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${DEV_NS}
resources:
  - ../../base
labels:
  - pairs:
      environment: dev
      demo.fxrate.act: "0"
    includeSelectors: false
commonAnnotations:
  demo.fxrate.image: 1.0.0-legacy
images:
  - name: ${repo}
    digest: ${LEGACY_DIGEST}
EOF

  # Empty prod overlay — Argo prune clears fxrate-prod (Act 0).
  cat >"$prod" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${PROD_NS}
resources: []
# Cleared by make reset (Act 0). Restore with make restore-act3b.
EOF

  log "GitOps files updated for Act 0 (dev=${LEGACY_DIGEST})"
}

commit_and_push() {
  need_git
  cd "$ROOT"
  if [[ -n "$(git status --porcelain --untracked-files=no | grep -v 'fx-rate-gitops/' || true)" ]] && [[ "$FORCE" != "1" ]]; then
    # allow dirty only inside gitops if FORCE unset — abort on other dirty tracked files
    local other
    other="$(git status --porcelain --untracked-files=no | grep -v 'fx-rate-gitops/' || true)"
    if [[ -n "$other" ]]; then
      die "working tree has non-gitops changes; commit/stash them or FORCE=1"$'\n'"$other"
    fi
  fi

  git add fx-rate-gitops/base/deployment.yaml \
         fx-rate-gitops/overlays/dev/kustomization.yaml \
         fx-rate-gitops/overlays/prod/kustomization.yaml

  if git diff --cached --quiet; then
    log "GitOps already at Act 0 pin — nothing to commit"
  else
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY_RUN: would commit Act 0 GitOps pin"
      git diff --cached --stat
      git reset HEAD >/dev/null
      return 0
    fi
    git commit -m "demo: reset GitOps to Act 0 (1.0.0-legacy) [skip ci]"
  fi

  if [[ "$SKIP_PUSH" == "1" ]]; then
    log "SKIP_PUSH=1 — not pushing; Argo will not see this until you push"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: would push origin HEAD:main"
    return 0
  fi
  git push origin HEAD:main
  log "pushed $(git rev-parse --short HEAD) → origin/main"
}

argo_sync() {
  local app="$1"
  local prune="${2:-false}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: would sync Argo app $app prune=$prune"
    return 0
  fi
  if [[ "$prune" == "true" ]]; then
    oc -n "$ARGO_NS" patch application "$app" --type merge -p \
      "{\"operation\":{\"initiatedBy\":{\"username\":\"make-reset\"},\"sync\":{\"revision\":\"HEAD\",\"prune\":true}}}"
  else
    oc -n "$ARGO_NS" patch application "$app" --type merge -p \
      "{\"operation\":{\"initiatedBy\":{\"username\":\"make-reset\"},\"sync\":{\"revision\":\"HEAD\"}}}"
  fi
}

wait_dev_act0() {
  if [[ "$DRY_RUN" == "1" ]] || [[ "$SKIP_PUSH" == "1" ]]; then
    log "skip wait (DRY_RUN or SKIP_PUSH)"
    return 0
  fi
  log "waiting for Argo + rollout on ${DEV_NS}"
  local i sync health img
  for i in $(seq 1 36); do
    sync="$(oc -n "$ARGO_NS" get application fx-rate-dev -o jsonpath='{.status.sync.status}' 2>/dev/null || echo '?')"
    health="$(oc -n "$ARGO_NS" get application fx-rate-dev -o jsonpath='{.status.health.status}' 2>/dev/null || echo '?')"
    img="$(oc -n "$DEV_NS" get deploy fx-rate-service -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')"
    echo "  t=${i} sync=${sync} health=${health}"
    if [[ "$sync" == "Synced" && "$health" == "Healthy" && "$img" == *"${LEGACY_DIGEST#sha256:}"* ]]; then
      break
    fi
    sleep 5
  done
  oc -n "$DEV_NS" rollout status deploy/fx-rate-service --timeout=180s || true

  local host
  host="$(oc -n "$DEV_NS" get route fx-rate-service -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -n "$host" ]]; then
    log "GET https://${host}/versions"
    curl -sk --max-time 15 "https://${host}/versions" || true
    echo
  fi
}

clear_prod() {
  argo_sync fx-rate-prod true
  if [[ "$DRY_RUN" == "1" ]] || [[ "$SKIP_PUSH" == "1" ]]; then
    return 0
  fi
  local i sync
  for i in $(seq 1 24); do
    sync="$(oc -n "$ARGO_NS" get application fx-rate-prod -o jsonpath='{.status.sync.status}' 2>/dev/null || echo '?')"
    echo "  prod t=${i} sync=${sync}"
    # After prune, deploy may be gone — that is success for Act 0.
    if ! oc -n "$PROD_NS" get deploy fx-rate-service >/dev/null 2>&1; then
      log "fxrate-prod: fx-rate-service deploy removed (Act 0 empty prod)"
      return 0
    fi
    sleep 5
  done
  log "warning: prod deploy may still exist — check Argo fx-rate-prod prune"
}

fallback_oc_set_image() {
  # Used when SKIP_PUSH=1 so presenter can still force Act 0 without waiting on Git.
  [[ "$SKIP_PUSH" == "1" ]] || return 0
  [[ "$DRY_RUN" == "1" ]] && { log "DRY_RUN: would oc set image on ${DEV_NS}"; return 0; }
  log "SKIP_PUSH fallback: oc set image on ${DEV_NS} (Argo may overwrite if auto-sync still on Act 3b pin)"
  oc -n "$DEV_NS" set image deploy/fx-rate-service "fx-rate-service=${LEGACY_REF}"
  oc -n "$DEV_NS" rollout status deploy/fx-rate-service --timeout=180s
}

main() {
  need_oc
  log "reset → Act 0 image ${LEGACY_REF}"
  pin_gitops_act0
  if [[ "$DRY_RUN" == "1" ]]; then
    commit_and_push
    argo_sync fx-rate-dev false
    clear_prod
    # Undo working-tree edits so DRY_RUN is side-effect free.
    git -C "$ROOT" checkout -- \
      fx-rate-gitops/base/deployment.yaml \
      fx-rate-gitops/overlays/dev/kustomization.yaml \
      fx-rate-gitops/overlays/prod/kustomization.yaml 2>/dev/null || true
    log "DRY_RUN complete (GitOps files restored)."
    return 0
  fi
  commit_and_push
  if [[ "$SKIP_PUSH" == "1" ]]; then
    fallback_oc_set_image
  else
    argo_sync fx-rate-dev false
    wait_dev_act0
    clear_prod
  fi
  log "Act 0 reset complete."
  log "Restore resting Act 3b with: RESET_CONFIRM=yes make restore-act3b"
}

main "$@"
