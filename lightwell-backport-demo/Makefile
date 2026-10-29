# Repo-root targets for the Python CVE Upgrade Demo.
# App/image targets live under fx-rate-service/Makefile.

.PHONY: reset restore-act3b reset-note help

help:
	@echo "make reset          RESET_CONFIRM=yes  — GitOps + Argo → Act 0 (clear prod)"
	@echo "make restore-act3b  RESET_CONFIRM=yes  — back to Act 3b on dev+prod"
	@echo "Options: DRY_RUN=1  SKIP_PUSH=1  FORCE=1"
	@echo "See cluster/docs/DEMO-RUNBOOK.md"

reset:
	@test -f fx-rate-service/digests.env || (echo "cp fx-rate-service/digests.env.example fx-rate-service/digests.env first" >&2; exit 1)
	bash cluster/demo/reset-to-act0.sh

restore-act3b:
	@test -f fx-rate-service/digests.env || (echo "cp fx-rate-service/digests.env.example fx-rate-service/digests.env first" >&2; exit 1)
	bash cluster/demo/restore-act3b.sh

reset-note:
	@echo "Use: RESET_CONFIRM=yes make reset"
	@echo "Restore: RESET_CONFIRM=yes make restore-act3b"
