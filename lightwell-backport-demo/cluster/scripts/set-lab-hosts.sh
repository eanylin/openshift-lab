#!/usr/bin/env bash
# Rewrite lab hostnames across the monorepo for a new cluster / GitHub-first lab.
#
# Usage:
#   cp cluster/lab.env.example cluster/lab.env   # edit APPS_DOMAIN
#   ./cluster/scripts/set-lab-hosts.sh           # apply
#   ./cluster/scripts/set-lab-hosts.sh --dry-run
#   ./cluster/scripts/set-lab-hosts.sh --from cluster/lab.env
#
# Strategy: replace SOURCE_APPS_DOMAIN → APPS_DOMAIN everywhere that matches.
# Derived hosts (quay./nexus./gitlab-gitlab./sso. + APPS_DOMAIN) rewrite automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT}/cluster/lab.env"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) ENV_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy cluster/lab.env.example and edit APPS_DOMAIN." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

SOURCE_APPS_DOMAIN="${SOURCE_APPS_DOMAIN:?set SOURCE_APPS_DOMAIN in lab.env}"
APPS_DOMAIN="${APPS_DOMAIN:?set APPS_DOMAIN in lab.env}"

if [[ "$SOURCE_APPS_DOMAIN" == "$APPS_DOMAIN" ]]; then
  echo "SOURCE_APPS_DOMAIN == APPS_DOMAIN ($APPS_DOMAIN) — nothing to rewrite."
  echo "Edit APPS_DOMAIN in $ENV_FILE for a new lab, then re-run."
  exit 0
fi

echo "Rewrite: ${SOURCE_APPS_DOMAIN}  →  ${APPS_DOMAIN}"
[[ "$DRY_RUN" == "1" ]] && echo "(dry-run — no writes)"

changed=0
while IFS= read -r -d '' path; do
  rel="${path#"${ROOT}/"}"
  case "$rel" in
    digests.env|*digests.env|._*|*/._*) continue ;;
  esac
  if ! grep -qF "$SOURCE_APPS_DOMAIN" "$path" 2>/dev/null; then
    continue
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo " would update  $rel"
  else
    SOURCE_APPS_DOMAIN="$SOURCE_APPS_DOMAIN" APPS_DOMAIN="$APPS_DOMAIN" python3 - "$path" <<'PY'
import os, sys
path = sys.argv[1]
old, new = os.environ["SOURCE_APPS_DOMAIN"], os.environ["APPS_DOMAIN"]
try:
    text = open(path, encoding="utf-8").read()
except UnicodeDecodeError:
    sys.exit(0)
if old not in text:
    sys.exit(0)
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    echo " updated  $rel"
  fi
  changed=$((changed + 1))
done < <(
  find "$ROOT" \
    \( -path "$ROOT/.git" -o -path "$ROOT/.venv" -o -path '*/__pycache__' -o -path '*/.pytest_cache' \) -prune -o \
    -type f \( \
      -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' -o \
      -name '*.env.example' -o -name '*.txt' -o -name '*.py' -o \
      -name 'Makefile' -o -name '*.toml' -o -name 'devfile.yaml' \
    \) -print0
)

echo "Files touched: $changed"
if [[ "$DRY_RUN" != "1" && "$changed" -gt 0 ]]; then
  if [[ -f "${ROOT}/cluster/lab.env.example" ]]; then
    SOURCE_APPS_DOMAIN="$SOURCE_APPS_DOMAIN" APPS_DOMAIN="$APPS_DOMAIN" python3 - "${ROOT}/cluster/lab.env.example" <<'PY'
import os, sys
path = sys.argv[1]
old, new = os.environ["SOURCE_APPS_DOMAIN"], os.environ["APPS_DOMAIN"]
text = open(path, encoding="utf-8").read()
text2 = text.replace(f"SOURCE_APPS_DOMAIN={old}", f"SOURCE_APPS_DOMAIN={new}")
text2 = text2.replace(f"APPS_DOMAIN={old}", f"APPS_DOMAIN={new}")
if text2 != text:
    open(path, "w", encoding="utf-8").write(text2)
    print(" updated  cluster/lab.env.example (SOURCE/APPS now match new lab)")
PY
  fi
  cat <<EOF

Next:
  1. Review: git diff --stat
  2. Rebuild/push Quay images (make *-image) and refresh digests.env + overlays
  3. bash cluster/tekton/setup-secrets.sh && bash cluster/tekton/setup-triggers.sh
  4. oc apply -f fx-rate-gitops/argocd/
EOF
fi
