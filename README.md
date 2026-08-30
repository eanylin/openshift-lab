# openshift-lab

OpenShift demos and lab assets — pinned ExploitIQ/RHTPA deploys, logging, backup/restore, agent-based install, and more.

| Folder | Description |
|--------|-------------|
| [agent-based-install](agent-based-install/) | Agent-based installation |
| [backup_restore_with_oadp_demo](backup_restore_with_oadp_demo/) | OADP backup/restore with external Ceph |
| [demo-openshift-logging-bastion](demo-openshift-logging-bastion/) | OpenShift Logging → bastion rsyslog, Loki, UWM, audit forwarding |
| [exploitiq-demo](exploitiq-demo/) | Pinned ExploitIQ on OpenShift — [getting started](exploitiq-demo/README.md), [demo walkthrough](exploitiq-demo/docs/demo-walkthrough.md) (+ optional RHTPA Exploit Intelligence) |
| [red-hat-ai](red-hat-ai/) | Red Hat AI |

## Secrets

Do not commit credentials. Each demo documents its own `env.local` / secrets files where applicable.
