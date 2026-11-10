#!/usr/bin/env bash
# SAAF Gatekeeper: fails when a secret is anywhere in git history, or when a .env file can be committed.
# Bash 3.2 compatible (macOS default shell).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$here/gitleaks.toml"
template="$here/report.tmpl"
env_template_re='(^|/)\.env(\.[^/]*)?\.(example|sample|template|dist)$'
env_file_re='(^|/)\.env(\.[^/]*)?$'
env_use_re='load_dotenv|dotenv'

usage() {
  cat <<'EOF'
Usage: gatekeeper.sh [--staged] [REPO]
       gatekeeper.sh --install-hook [REPO]

  REPO            git repository to check (default: current directory)
  (no flag)       scan every commit on every branch, then check .env handling
  --staged        pre-commit mode: scan only what is staged for the next commit
  --install-hook  write a pre-commit hook into REPO that runs --staged

Exit codes: 0 clean, 1 findings, 2 setup error.
EOF
}

mode=history
case "${1:-}" in
  --staged) mode=staged; shift ;;
  --install-hook) mode=install; shift ;;
  -h|--help) usage; exit 0 ;;
  -*) usage >&2; exit 2 ;;
esac
repo="${1:-.}"

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "gatekeeper: $repo is not a git repository" >&2
  exit 2
fi
repo="$(git -C "$repo" rev-parse --show-toplevel)"

if [ "$mode" = install ]; then
  hook="$(git -C "$repo" rev-parse --git-path hooks/pre-commit)"
  case "$hook" in /*) ;; *) hook="$repo/$hook" ;; esac
  if [ -e "$hook" ]; then
    echo "gatekeeper: $hook already exists; add this line to it instead:" >&2
    echo "  \"$here/gatekeeper.sh\" --staged || exit 1" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$hook")"
  printf '#!/usr/bin/env bash\nexec "%s/gatekeeper.sh" --staged\n' "$here" > "$hook"
  chmod +x "$hook"
  echo "gatekeeper: pre-commit hook installed at $hook"
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gatekeeper: gitleaks not found. Install it: brew install gitleaks, or https://github.com/gitleaks/gitleaks/releases" >&2
  exit 2
fi

if [ "$mode" = history ] && [ "$(git -C "$repo" rev-parse --is-shallow-repository)" = true ]; then
  echo "gatekeeper: $repo is a shallow clone, so its history is incomplete. In CI, check out with fetch-depth: 0." >&2
  exit 2
fi

report="$(mktemp)"
trap 'rm -f "$report"' EXIT
found=0

# --redact keeps secret values out of the output; the template leaves out author names and emails.
gitleaks_args=(--config "$config" --redact --no-banner --log-level error
  --report-format template --report-template "$template" --report-path "$report")
if [ "$mode" = staged ]; then
  gitleaks git "$repo" --pre-commit --staged "${gitleaks_args[@]}"
else
  gitleaks git "$repo" --log-opts=--all "${gitleaks_args[@]}"
fi
rc=$?
if grep -q '^FAIL' "$report"; then
  grep '^FAIL' "$report"
  found=1
elif [ "$rc" -ne 0 ]; then
  echo "gatekeeper: gitleaks failed (exit $rc)" >&2
  exit 2
fi

if [ "$mode" = staged ]; then
  candidates="$(git -C "$repo" diff --cached --name-only --diff-filter=ACMR)"
else
  candidates="$(git -C "$repo" ls-files)"
fi
while IFS= read -r path; do
  [ -z "$path" ] && continue
  echo "FAIL env     $path is committed; only .env.example (placeholders) belongs in git"
  found=1
done <<EOF
$(printf '%s\n' "$candidates" | grep -E "$env_file_re" | grep -v -E "$env_template_re")
EOF

# Every folder that ships a .env template, or holds a file that loads dotenv, must ignore its .env.
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  target=".env"
  [ "$dir" != . ] && target="$dir/.env"
  if ! git -C "$repo" check-ignore -q --no-index "$target"; then
    echo "FAIL env     $target is not git-ignored, so 'git add .' would commit it"
    found=1
  fi
done <<EOF
$( {
  git -C "$repo" grep -l -I -E "$env_use_re" -- . ':!*ignore' ':!*.md'
  git -C "$repo" ls-files | grep -E "$env_template_re"
} | while IFS= read -r f; do dirname "$f"; done | sort -u)
EOF

if [ "$found" -eq 1 ]; then
  cat <<'EOF'

How to fix:
  secret  Revoke the key at its provider first: deleting the file or rewriting history does not
          un-leak it. Then add the fingerprint above to .gitleaksignore so the check passes.
  env     Add .env to .gitignore. Keep only placeholders in .env.example.
EOF
  exit 1
fi

if [ "$mode" = staged ]; then
  echo "OK  no secrets or .env files in the staged changes"
else
  echo "OK  no secrets in any commit on any branch; .env files are git-ignored"
fi
