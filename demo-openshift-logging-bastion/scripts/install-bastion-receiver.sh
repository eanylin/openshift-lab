#!/usr/bin/env bash
# install-bastion-receiver.sh — configure rsyslog + logrotate on the RHEL bastion.
# Run on the bastion as root (or via sudo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

install -m 644 "${ROOT}/bastion/rsyslog/openshift-remote.conf" /etc/rsyslog.d/openshift-remote.conf
install -m 644 "${ROOT}/bastion/logrotate/openshift-remote" /etc/logrotate.d/openshift-remote
install -m 644 "${ROOT}/bastion/logrotate/hourly-logrotate.cron" /etc/cron.d/openshift-remote-logrotate

systemctl restart rsyslog
systemctl is-active rsyslog

echo "rsyslog listeners:"
ss -tlnp | grep -E '514|10514' || true

echo ""
echo "Optional: force initial rotation if log already large"
echo "  logrotate -f /etc/logrotate.d/openshift-remote"
echo ""
echo "Log file: /var/log/openshift-remote.log"
