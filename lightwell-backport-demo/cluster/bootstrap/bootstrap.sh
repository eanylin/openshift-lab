# Cluster bootstrap helpers for the Python CVE upgrade demo (P0).
# Does NOT install RHACS (already present on the lab) or Nexus image pull secrets.

set -euo pipefail

NS_CI="${FXRATE_CI_NS:-fxrate-ci}"
NS_DEV="${FXRATE_DEV_NS:-fxrate-dev}"
NS_PROD="${FXRATE_PROD_NS:-fxrate-prod}"
NS_NEXUS="${NEXUS_NS:-nexus}"

need_oc() {
  command -v oc >/dev/null || { echo "oc not found" >&2; exit 1; }
  oc whoami >/dev/null || { echo "oc not logged in" >&2; exit 1; }
}

cmd_namespaces() {
  need_oc
  for ns in "$NS_CI" "$NS_DEV" "$NS_PROD" "$NS_NEXUS"; do
    oc create namespace "$ns" --dry-run=client -o yaml | oc apply -f -
    oc label namespace "$ns" app.kubernetes.io/part-of=fx-rate-demo --overwrite
  done
  echo "Namespaces ready: $NS_CI $NS_DEV $NS_PROD $NS_NEXUS"
}

cmd_status() {
  need_oc
  echo "=== namespaces ==="
  oc get ns "$NS_CI" "$NS_DEV" "$NS_PROD" "$NS_NEXUS" 2>&1 || true
  echo "=== RHACS ==="
  oc get central,securedcluster -n rhacs-operator 2>&1 || true
  echo "=== GitOps ==="
  oc get application -n openshift-gitops 2>&1 | grep -E 'fx-rate|NAME' || true
}

usage() {
  cat <<EOF
Usage: $0 <namespaces|status>

  namespaces  Create fxrate-ci, fxrate-dev, fxrate-prod, nexus
  status      Show demo-related cluster status

Nexus, ACS, Triggers, and host parameterization: see cluster/docs/BOOTSTRAP.md.
EOF
}

main() {
  case "${1:-}" in
    namespaces) cmd_namespaces ;;
    status) cmd_status ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
