#!/usr/bin/env bash
# Builds throwaway repos with a generated fake key (never a real one) and checks gatekeeper's verdicts.
set -uo pipefail

gk="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gatekeeper.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
fake_key="sk-ant-api03-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 93)AA"
failed=0

new_repo() {
  rm -rf "$work/r" && git init -q -b main "$work/r" && cd "$work/r" || exit 2
}

expect() {
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL  $name: exit $rc, want $want"; echo "$out" | sed 's/^/      /'; failed=1
  elif printf '%s' "$out" | grep -q -F "$fake_key"; then
    echo "FAIL  $name: secret value printed"; failed=1
  else
    echo "ok    $name"
  fi
}

new_repo
printf '.env\n' > .gitignore
printf 'from dotenv import load_dotenv\nload_dotenv()\n' > main.py
printf 'ANTHROPIC_API_KEY=your-key-here\n' > .env.example
git add . && git commit -q -m clean
expect "clean repo passes" 0 "$gk" .

new_repo
printf '.env\n' > .gitignore
printf 'ANTHROPIC_API_KEY=%s\n' "$fake_key" > .env.example
git add . && git commit -q -m leak
git rm -q .env.example && git commit -q -m "delete the key"
expect "key deleted in a later commit still fails" 1 "$gk" .

new_repo
printf '.env\n' > .gitignore
git commit -q --allow-empty -m init
git checkout -q -b feature
printf 'ANTHROPIC_API_KEY=%s\n' "$fake_key" > config.txt
git add . && git commit -q -m leak
git checkout -q main
expect "key on another branch fails" 1 "$gk" .

new_repo
printf 'from dotenv import load_dotenv\nload_dotenv()\n' > main.py
git add . && git commit -q -m "no gitignore"
expect "dotenv user without .env ignored fails" 1 "$gk" .

new_repo
printf 'DEBUG=1\n' > .env
git add . && git commit -q -m "tracked env"
expect "committed .env fails" 1 "$gk" .

new_repo
printf 'const SUGGESTIONS_KEY = "a2-eval-suggestions";\n' > page.js
git add . && git commit -q -m identifier
expect "hyphenated identifier is not a secret" 0 "$gk" .

new_repo
printf '.env\n' > .gitignore
git add . && git commit -q -m init
printf 'ANTHROPIC_API_KEY=%s\n' "$fake_key" > settings.py
git add settings.py
expect "pre-commit blocks a staged key" 1 "$gk" --staged .
git reset -q settings.py && rm settings.py
expect "pre-commit passes clean staged changes" 0 "$gk" --staged .

git clone -q --depth 1 "file://$work/r" "$work/shallow"
expect "shallow clone is refused" 2 "$gk" "$work/shallow"

exit "$failed"
