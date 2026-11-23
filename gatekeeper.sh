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
if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi
repo="${1:-.}"

incomplete() {
  echo "gatekeeper: incomplete inspection: $*" >&2
  exit 2
}

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "gatekeeper: $repo is not a git repository" >&2
  exit 2
fi
repo="$(git -C "$repo" rev-parse --show-toplevel)" || incomplete "cannot resolve repository root"

if [ "$mode" = install ]; then
  hook="$(git -C "$repo" rev-parse --git-path hooks/pre-commit)" || incomplete "cannot resolve hook location"
  case "$hook" in /*) ;; *) hook="$repo/$hook" ;; esac
  if [ -e "$hook" ] || [ -L "$hook" ]; then
    echo "gatekeeper: $hook already exists; add this line to it instead:" >&2
    echo "  \"$here/gatekeeper.sh\" --staged || exit 1" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$hook")" || incomplete "cannot create hooks directory"
  printf '#!/usr/bin/env bash\nexec %q --staged\n' "$here/gatekeeper.sh" > "$hook" || incomplete "cannot write hook"
  chmod +x "$hook" || incomplete "cannot mark hook executable"
  echo "gatekeeper: pre-commit hook installed at $hook"
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gatekeeper: gitleaks not found. Install it: brew install gitleaks, or https://github.com/gitleaks/gitleaks/releases" >&2
  exit 2
fi

if [ "$mode" = history ]; then
  shallow="$(git -C "$repo" rev-parse --is-shallow-repository)" || incomplete "cannot determine history completeness"
  case "$shallow" in
    false) ;;
    true) incomplete "shallow clone; check out with fetch-depth: 0" ;;
    *) incomplete "unknown history completeness" ;;
  esac
fi

report="$(mktemp)" || incomplete "cannot create temporary report"
policy=""
trap 'rm -f "$report"; [ -z "$policy" ] || rm -rf "$policy"' EXIT
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
case "$rc" in 0|1) ;; *) incomplete "gitleaks failed (exit $rc)" ;; esac
reported="$(grep '^FAIL' "$report")"
report_status=$?
if [ "$report_status" -eq 0 ]; then
  [ "$rc" -eq 1 ] || incomplete "gitleaks verdict and report disagree"
  printf '%s\n' "$reported"
  found=1
elif [ "$report_status" -ne 1 ]; then
  incomplete "cannot read gitleaks report"
elif [ "$rc" -ne 0 ]; then
  echo "gatekeeper: gitleaks failed (exit $rc)" >&2
  exit 2
fi

if [ "$mode" = staged ]; then
  candidates="$(git -C "$repo" -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR)" || incomplete "cannot read staged paths"
else
  candidates="$(git -C "$repo" -c core.quotePath=false ls-files)" || incomplete "cannot read tracked paths"
fi
tracked="$(git -C "$repo" -c core.quotePath=false ls-files)" || incomplete "cannot enumerate index"
# Git quotes paths containing control characters or quotes. Do not turn those
# line-oriented records into partial or misleading .env checks.
if printf '%s\n%s\n' "$tracked" "$candidates" | grep -q '^"'; then
  incomplete "quoted/control-character paths require manual review"
fi
while IFS= read -r path; do
  [ -z "$path" ] && continue
  echo "FAIL env     $path is committed; only .env.example (placeholders) belongs in git"
  found=1
done <<EOF
$(printf '%s\n' "$candidates" | grep -E "$env_file_re" | grep -v -E "$env_template_re")
EOF

# Read dotenv usage from the index, not unstaged source. Exit 1 means no matches;
# any other grep error is missing evidence.
dotenv_files="$(git -C "$repo" -c core.quotePath=false grep --cached -l -I -E "$env_use_re" -- . ':!*ignore' ':!*.md')"
rc=$?
case "$rc" in 0|1) ;; *) incomplete "cannot inspect indexed dotenv usage" ;; esac

# Check the committed/staged ignore policy in isolation. A local/global exclude
# or an unstaged .gitignore must not conceal what the next checkout would allow.
policy="$(mktemp -d)" || incomplete "cannot create ignore-policy snapshot"
policy_git() {
  env -i PATH="$PATH" HOME="$policy" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$policy" "$@"
}
policy_git init -q || incomplete "cannot initialize ignore-policy snapshot"
while IFS= read -r path; do
  case "$path" in .gitignore|*/.gitignore) ;; *) continue ;; esac
  entry="$(git -C "$repo" ls-files --stage -- "$path")" || incomplete "cannot read ignore-file mode"
  case "$entry" in 100644\ *|100755\ *) ;; *) incomplete "ignore policy must be an ordinary indexed file" ;; esac
  mkdir -p "$policy/$(dirname "$path")" || incomplete "cannot prepare ignore-policy directory"
  git -C "$repo" show ":$path" > "$policy/$path" || incomplete "cannot read indexed ignore policy"
done <<EOF
$tracked
EOF

# Every folder shipping an env template or indexed dotenv code must ignore .env.
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  target=".env"
  [ "$dir" != . ] && target="$dir/.env"
  policy_git check-ignore -q --no-index "$target"
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "FAIL env     $target is not git-ignored, so 'git add .' would commit it"
    found=1
  elif [ "$rc" -ne 0 ]; then
    incomplete "cannot evaluate indexed ignore policy"
  fi
done <<EOF
$( {
  printf '%s\n' "$dotenv_files"
  printf '%s\n' "$tracked" | grep -E "$env_template_re"
} | while IFS= read -r f; do [ -z "$f" ] || dirname "$f"; done | sort -u)
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
