#!/usr/bin/env bash
# verify.sh — quick health checks (run from bastion after oc login).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/config/env.local"
[[ -f "$CONFIG" ]] && source "$CONFIG"

ok() { printf '  OK  %s\n' "$*"; }
warn() { printf '  ??  %s\n' "$*"; }

echo "=== OpenShift ==="
if oc whoami >/dev/null 2>&1; then
  ok "oc logged in as $(oc whoami)"
else
  warn "not logged in — oc login required"
  exit 1
fi

phase="$(oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo unknown)"
[[ "$phase" == "True" ]] && ok "ClusterLogForwarder Ready" || warn "ClusterLogForwarder Ready=$phase"

running="$(oc get pods -n openshift-logging --no-headers 2>/dev/null | awk '$2=="1/1" {c++} END{print c+0}')"
ok "openshift-logging pods ready: $running"

loki="$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo unknown)"
[[ "$loki" == "True" ]] && ok "LokiStack Ready" || warn "LokiStack Ready=$loki"

uwm="$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | grep -c Running || echo 0)"
[[ "$uwm" -ge 3 ]] && ok "user-workload monitoring pods running ($uwm)" || warn "UWM pods=$uwm"

echo ""
echo "=== Bastion syslog (if on bastion) ==="
if [[ -f /var/log/openshift-remote.log ]]; then
  ls -lh /var/log/openshift-remote.log* 2>/dev/null | sed 's/^/  /'
  df -h / | tail -1 | sed 's/^/  /'
else
  warn "/var/log/openshift-remote.log not found — run install-bastion-receiver.sh on bastion"
fi

echo ""
echo "=== Sample queries (bastion) ==="
echo "  sudo grep 'namespace_name=hello-world-app' /var/log/openshift-remote.log | tail -5"
echo "  sudo grep 'log_type=audit' /var/log/openshift-remote.log | tail -5"
