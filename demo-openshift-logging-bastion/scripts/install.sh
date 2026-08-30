#!/usr/bin/env bash
# install.sh — deploy OpenShift logging stack + bastion syslog forwarding (cluster side).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/config/env.local"

if [[ -f "$CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG"
else
  echo "Missing $CONFIG — copy config/env.example to config/env.local" >&2
  exit 1
fi

: "${BASTION_SYSLOG_HOST:?Set BASTION_SYSLOG_HOST in config/env.local}"
: "${BASTION_SYSLOG_PORT:=514}"
: "${LOGGING_CHANNEL:=stable-6.6}"
: "${LOKI_CHANNEL:=stable-6.6}"
: "${COO_CHANNEL:=stable}"
: "${STORAGE_CLASS:=gp3-csi}"
: "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER in config/env.local}"
: "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD in config/env.local}"
: "${MINIO_BUCKET:=loki}"
: "${DEMO_APP_NAMESPACE:=hello-world-app}"

oc whoami >/dev/null 2>&1 || { echo "Run oc login first" >&2; exit 1; }
oc auth can-i '*' '*' --all-namespaces >/dev/null 2>&1 || {
  echo "cluster-admin required" >&2
  exit 1
}

step() { printf '\n==> %s\n' "$*"; }

patch_subscription_channel() {
  local ns="$1" name="$2" channel="$3"
  oc patch subscription "$name" -n "$ns" --type merge \
    -p "{\"spec\":{\"channel\":\"$channel\",\"sourceNamespace\":\"openshift-marketplace\"}}" 2>/dev/null || true
}

step "Namespaces + user workload monitoring"
oc apply -f "${ROOT}/openshift/00-namespaces.yaml"
oc apply -f "${ROOT}/openshift/01-user-workload-monitoring.yaml"

step "Operator subscriptions"
oc apply -f "${ROOT}/openshift/02-logging-operator.yaml"
oc apply -f "${ROOT}/openshift/03-loki-operator.yaml"
oc apply -f "${ROOT}/openshift/04-coo-operator.yaml"
patch_subscription_channel openshift-logging cluster-logging "$LOGGING_CHANNEL"
patch_subscription_channel openshift-operators-redhat loki-operator "$LOKI_CHANNEL"
patch_subscription_channel openshift-operators cluster-observability-operator "$COO_CHANNEL"

step "Waiting for cluster-logging CSV"
for i in $(seq 1 60); do
  phase="$(oc get csv -n openshift-logging -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Succeeded" ]] && break
  sleep 10
done
oc get csv -n openshift-logging

step "Collector service account + RBAC"
"${ROOT}/scripts/enable-audit-forwarding.sh" --rbac-only

step "MinIO credentials + Loki S3 secret (from env.local — not stored in git)"
oc create secret generic minio-credentials -n openshift-logging \
  --from-literal=MINIO_ROOT_USER="$MINIO_ROOT_USER" \
  --from-literal=MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -

oc create secret generic logging-loki-s3 -n openshift-logging \
  --from-literal=access_key_id="$MINIO_ROOT_USER" \
  --from-literal=access_key_secret="$MINIO_ROOT_PASSWORD" \
  --from-literal=bucketnames="$MINIO_BUCKET" \
  --from-literal=endpoint="http://minio.openshift-logging.svc:9000" \
  --from-literal=region="us-east-1" \
  --dry-run=client -o yaml | oc apply -f -

step "MinIO deployment"
sed "s/storageClassName: gp3-csi/storageClassName: ${STORAGE_CLASS}/" \
  "${ROOT}/openshift/05-minio.yaml" | oc apply -f -
oc wait --for=condition=Available deployment/minio -n openshift-logging --timeout=300s
oc exec -n openshift-logging deploy/minio -- sh -c "mkdir -p /data/${MINIO_BUCKET}" 2>/dev/null || true

step "Waiting for Loki operator CSV"
for i in $(seq 1 60); do
  phase="$(oc get csv -n openshift-operators-redhat -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Succeeded" ]] && break
  sleep 10
done

step "LokiStack"
sed "s/storageClassName: gp3-csi/storageClassName: ${STORAGE_CLASS}/" \
  "${ROOT}/openshift/07-lokistack.yaml" | oc apply -f -
oc wait --for=condition=Ready lokistack/logging-loki -n openshift-logging --timeout=600s || true

step "ClusterLogForwarder (bastion syslog + Loki)"
generated="${ROOT}/openshift/09-clusterlogforwarder.generated.yaml"
sed -e "s/__BASTION_SYSLOG_HOST__/${BASTION_SYSLOG_HOST}/g" \
    -e "s/__BASTION_SYSLOG_PORT__/${BASTION_SYSLOG_PORT}/g" \
  "${ROOT}/openshift/09-clusterlogforwarder.yaml.template" > "$generated"
oc apply -f "$generated"

step "Console logging UI"
oc apply -f "${ROOT}/openshift/10-uiplugin.yaml"

if oc get namespace "$DEMO_APP_NAMESPACE" >/dev/null 2>&1; then
  step "Label demo namespace for user-workload monitoring: $DEMO_APP_NAMESPACE"
  oc label namespace "$DEMO_APP_NAMESPACE" openshift.io/cluster-monitoring=true --overwrite
fi

step "Enable audit forwarding (optional high volume)"
"${ROOT}/scripts/enable-audit-forwarding.sh"

echo ""
echo "Cluster install complete. Next on bastion:"
echo "  sudo ${ROOT}/scripts/install-bastion-receiver.sh"
echo "  ${ROOT}/scripts/verify.sh"
