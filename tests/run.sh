#!/usr/bin/env bash
# Builds throwaway repos with a generated fake key (never a real one) and checks gatekeeper's verdicts.
set -uo pipefail

gk="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gatekeeper.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
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

new_repo
printf '.env\n' > .gitignore
printf 'load_dotenv()\n' > main.py
git add . && git commit -q -m "indexed ignore policy"
: > .gitignore
git add .gitignore
printf '.env\n' > .gitignore
expect "unstaged ignore cannot hide its staged removal" 1 "$gk" --staged .
git add .gitignore
: > .gitignore
expect "indexed ignore is used despite an unstaged working-tree removal" 0 "$gk" --staged .

new_repo
printf 'load_dotenv()\n' > main.py
git add . && git commit -q -m "no shared ignore policy"
printf '.env\n' > .git/info/exclude
expect "local excludes do not substitute for an indexed policy" 1 "$gk" .

new_repo
printf 'safe fixture\n' > README.md
git add . && git commit -q -m "safe fixture"
real_git="$(command -v git)"
mkdir -p "$work/fault-git" "$work/fault-gitleaks"
cat > "$work/fault-git/git" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" != "$FAIL_GIT_OPERATION" ] || exit 128
done
exec "$REAL_GIT" "$@"
SH
chmod +x "$work/fault-git/git"
expect "failed git path enumeration is unknown" 2 env PATH="$work/fault-git:$PATH" REAL_GIT="$real_git" FAIL_GIT_OPERATION=ls-files "$gk" .
expect "failed git grep is unknown, not no matches" 2 env PATH="$work/fault-git:$PATH" REAL_GIT="$real_git" FAIL_GIT_OPERATION=grep "$gk" .

cat > "$work/fault-gitleaks/gitleaks" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = --report-path ]; then
    printf 'FAIL secret synthetic-placeholder\n' > "$2"
    break
  fi
  shift
done
exit 2
SH
chmod +x "$work/fault-gitleaks/gitleaks"
expect "partial findings never hide a gitleaks failure" 2 env PATH="$work/fault-gitleaks:$PATH" "$gk" .
cat > "$work/fault-gitleaks/gitleaks" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = --report-path ]; then rm -f "$2"; break; fi
  shift
done
exit 0
SH
expect "missing scanner report remains unknown" 2 env PATH="$work/fault-gitleaks:$PATH" "$gk" .
expect "unexpected extra repository argument is refused" 2 "$gk" . extra-repo

ln -s "$work/absent-hook" .git/hooks/pre-commit
expect "existing dangling hook symlink is preserved" 2 "$gk" --install-hook .
[ -L .git/hooks/pre-commit ] || { echo "FAIL  existing hook symlink was overwritten"; failed=1; }
rm .git/hooks/pre-commit
mkdir -p "$work/tool-\$literal"
cp "$gk" "$(dirname "$gk")/gitleaks.toml" "$(dirname "$gk")/report.tmpl" "$work/tool-\$literal/"
expect "hook installs with literal shell characters in tool path" 0 "$work/tool-\$literal/gatekeeper.sh" --install-hook .
expect "installed hook preserves its exact tool path" 0 .git/hooks/pre-commit

mkdir -p "$work/sweep-tool"
cp "$(dirname "$gk")/demo.sh" "$work/sweep-tool/demo.sh"
cat > "$work/sweep-tool/gatekeeper.sh" <<'SH'
#!/usr/bin/env bash
if [ "$SWEEP_FIXTURE_EXIT" -eq 1 ]; then echo 'FAIL env synthetic fixture'; fi
exit "$SWEEP_FIXTURE_EXIT"
SH
chmod +x "$work/sweep-tool/gatekeeper.sh"
expect "sweep preserves scanner error" 2 env SWEEP_FIXTURE_EXIT=2 bash "$work/sweep-tool/demo.sh" "$work" r
expect "sweep preserves finding exit" 1 env SWEEP_FIXTURE_EXIT=1 bash "$work/sweep-tool/demo.sh" "$work" r
expect "sweep reports successful synthetic input" 0 env SWEEP_FIXTURE_EXIT=0 bash "$work/sweep-tool/demo.sh" "$work" r
expect "sweep refuses missing explicitly requested input" 2 env SWEEP_FIXTURE_EXIT=0 bash "$work/sweep-tool/demo.sh" "$work" absent

exit "$failed"
