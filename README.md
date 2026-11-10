# SAAF Gatekeeper

Stops API keys from reaching git history, and stops `.env` files from being committed. One script,
used three ways: a pre-commit hook on the laptop, a CI check on every push, and a sweep over a folder of
SAAF repos.

## What it stops

Found on 2026-11-10 in the SAAF-Project repos (values redacted, never printed):

| Repo | What Gatekeeper reports |
|---|---|
| ExecGRC | `anthropic-api-key` in commit `22177ad`, `.env.example:23`. The file was deleted 4 minutes later; the key is still in history. |
| Team-HighTable | `anthropic-api-key` and `generic-api-key` in commit `1294181`, `backend/.env:4` and `:2`. Deleted 6 minutes later; still in history. |
| Track-4-Audit-Report-Generator | `.env` and `app/.env` not git-ignored (no `.gitignore` at all), while `main.py:12` calls `load_dotenv()` and the README says `cp .env.example .env`. |
| Stress-test---standalone-criteria | `.env` and `app/.env` not git-ignored, while `.env.example` says "copy this file to .env" and `app/chatbot.py:27` loads it. Public repo. |

Both leaked keys went straight to `main` without a pull request, so a PR-only check would never have
run. None of the 22 audit agent repos has a pre-commit hook or a CI secret scan (checked 2026-11-10).

## Where it runs, and why all three

| Layer | When | Effect |
|---|---|---|
| Pre-commit hook (`--staged`) | Before the commit exists | Prevents: the key never leaves the laptop |
| CI on every push, all branches, full history | After the push | Detects: cannot be skipped, catches old leaks |
| `demo.sh` sweep | On demand | Audits every clone in a folder |

A check that only runs on pull requests is too late and too narrow: the commit is already on GitHub when
it runs, and a direct push to `main` skips it. Only the hook prevents; CI is the backstop.

## How to run

Needs `git` and [gitleaks](https://github.com/gitleaks/gitleaks) 8.30+ (`brew install gitleaks`).

```bash
./gatekeeper.sh ~/workspace/saaf/ExecGRC          # full history, every branch, plus .env checks
./gatekeeper.sh --staged .                        # only what is staged (pre-commit mode)
./gatekeeper.sh --install-hook ~/code/my-agent    # write .git/hooks/pre-commit that runs --staged
./demo.sh ~/workspace/saaf                        # sweep every repo in the folder (2m23s for 47 repos)
./demo.sh ~/workspace/saaf ExecGRC Team-HighTable Track-4-Audit-Report-Generator Vendor_Guard
tests/run.sh                                      # 9 self-tests on throwaway repos with a generated fake key
```

Exit codes: `0` clean, `1` findings, `2` setup error (gitleaks missing, not a repo, shallow clone).

**CI**: copy [`examples/gatekeeper.yml`](examples/gatekeeper.yml) to `.github/workflows/` in any SAAF repo.
It needs `fetch-depth: 0`; Gatekeeper refuses a shallow clone instead of passing on half the history.
Pin `SAAF-Project/saaf-gatekeeper` to a commit SHA once it is published.

**pre-commit framework**:

```yaml
repos:
  - repo: https://github.com/SAAF-Project/saaf-gatekeeper
    rev: <commit sha>
    hooks:
      - id: saaf-gatekeeper
```

## What it checks

1. **Secrets in history.** gitleaks default rules (provider rules such as Anthropic, OpenAI, AWS and
   GitHub, plus an entropy-based `generic-api-key`) over `git log --all`. Output is redacted and leaves out
   author names and emails.
2. **Committed env files.** Any tracked `.env` or `.env.*` other than a template
   (`.env.example`, `.env.sample`, `.env.template`, `.env.dist`, including `.env.local.example`).
3. **Unignored env files.** Every folder that ships a `.env` template, or holds a file that uses
   `dotenv`, must have its `.env` git-ignored, so that `git add .` cannot pick it up.

## After a finding

- **Secret:** revoke the key at the provider first. Deleting the file, or rewriting history, does not
  un-leak a key someone may already have cloned. Then add the printed fingerprint to `.gitleaksignore` in
  the repo root so the check passes.
- **env:** add `.env` to `.gitignore`, and keep only placeholders in `.env.example`.

## Limitations

- **Pattern matching.** A key with a known prefix or high entropy is caught; a weak hand-made secret is
  not. `BACKEND_API_KEY` in the same Team-HighTable file was not flagged.
- **The hook is opt-in.** Each clone has to install it, and `git commit --no-verify` skips it. CI catches
  what slips through, but by then the key is on GitHub and must be revoked.
- **Nothing server-side.** Blocking the push itself needs GitHub push protection, which private repos
  only get with the paid GitHub Secret Protection add-on. 16 of the 22 audit agent repos are private.
- **Git only.** It does not scan PR descriptions, issues, Actions logs, forks, or files outside git.
- **dotenv only.** The ignore check knows `dotenv` and `.env` templates; other local config files
  (`secrets.yaml`, `config.local.json`) are covered only by the secret patterns.
- **One generic allowlist.** Short words joined by `-` or `/` (for example `a2-eval-suggestions`,
  `Claude/Anthropic`) are not reported by `generic-api-key`. These were the only false positives across
  the 47 repos. Provider rules are unaffected.
- The GitHub Action installs the Linux x64 gitleaks binary (checksum pinned), so it needs an
  `ubuntu-*` runner.
