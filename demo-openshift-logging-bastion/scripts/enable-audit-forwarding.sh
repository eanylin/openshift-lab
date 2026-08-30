#!/usr/bin/env bash
# enable-audit-forwarding.sh — grant audit RBAC and add audit to ClusterLogForwarder.
set -euo pipefail

RBAC_ONLY=false
[[ "${1:-}" == "--rbac-only" ]] && RBAC_ONLY=true

oc create sa collector -n openshift-logging 2>/dev/null || true
oc adm policy add-cluster-role-to-user collect-application-logs \
  system:serviceaccount:openshift-logging:collector 2>/dev/null || true
oc adm policy add-cluster-role-to-user collect-infrastructure-logs \
  system:serviceaccount:openshift-logging:collector 2>/dev/null || true
oc adm policy add-cluster-role-to-user collect-audit-logs \
  system:serviceaccount:openshift-logging:collector

if [[ "$RBAC_ONLY" == true ]]; then
  exit 0
fi

# Add audit to first pipeline if not already present
if ! oc get clusterlogforwarder instance -n openshift-logging \
  -o jsonpath='{.spec.pipelines[0].inputRefs}' | grep -q audit; then
  oc patch clusterlogforwarder instance -n openshift-logging --type=json \
    -p='[{"op":"add","path":"/spec/pipelines/0/inputRefs/-","value":"audit"}]'
fi

oc get clusterlogforwarder instance -n openshift-logging \
  -o jsonpath='Authorized: {.status.conditions[?(@.type=="observability.openshift.io/Authorized")].message}{"\n"}'
