# SAAF Gatekeeper

Detects matched secret patterns and unsafe indexed `.env` handling before an authorized commit or during CI. One script,
used three ways: a pre-commit hook on the laptop, a CI check on every push, and a sweep over a folder of
SAAF repos.

## What it checks

Gatekeeper checks provider-shaped/high-entropy candidate secrets, tracked env files and shared dotenv ignore policy. Earlier repository-specific observations remain in Git history; their private source dossiers and current remediation are not reproduced here. Sensitive finding details belong in a restricted register, not this public summary.

## Where it runs, and why all three

| Layer | When | Effect |
|---|---|---|
| Pre-commit hook (`--staged`) | Before the commit exists | Prevents: the key never leaves the laptop |
| CI on every push, all branches, full history | After the push | Detects after push when enabled, including known patterns in available history |
| `demo.sh` sweep | On demand | Audits every clone in a folder |

A check that only runs on pull requests is too late and too narrow: the commit is already on GitHub when
it runs, and a direct push to `main` skips it. A hook can prevent a matching commit when installed and not bypassed; enabled CI is a separate backstop.

## How to run

Needs Bash 3.2+, Git 2.28+ and [gitleaks](https://github.com/gitleaks/gitleaks). Version 8.30.1 is tested; other versions require validation. The Action/CI Linux installer pins its release checksum in `scripts/install-gitleaks.sh`. Native requirements are recorded in [requirements.txt](requirements.txt).

```bash
./gatekeeper.sh ~/workspace/saaf/ExecGRC          # full history, every branch, plus .env checks
./gatekeeper.sh --staged .                        # only what is staged (pre-commit mode)
./gatekeeper.sh --install-hook ~/code/my-agent    # write .git/hooks/pre-commit that runs --staged
./demo.sh ~/workspace/saaf                        # sweep every repo in the folder (2m23s for 47 repos)
./demo.sh ~/workspace/saaf ExecGRC Team-HighTable Track-4-Audit-Report-Generator Vendor_Guard
tests/run.sh                                      # 24 self-tests on throwaway repos with a generated fake key
```

Exit codes: `0` no known findings in the inspected scope, `1` findings, `2` setup or incomplete-inspection error (including failed Git operations, scanner failure and shallow history).

**CI**: copy [`examples/gatekeeper.yml`](examples/gatekeeper.yml) to `.github/workflows/` in any SAAF repo.
It needs `fetch-depth: 0`; Gatekeeper refuses a shallow clone instead of passing on half the history.
The example is pinned to the existing main revision `3664690a3bc26f49f5d0cb223ba755d76b676c61`; adopting newer candidate fixes requires a separately reviewed repin. This repository’s own PR-CI tests the candidate in synthetic repos and does not authorize an automatic merge.

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
   `dotenv`, must have `.env` ignored by the indexed `.gitignore` policy. Unstaged changes and developer-only excludes cannot substitute for policy that travels with the commit.

## After a finding

- **Secret:** revoke the key at the provider first. Deleting the file, or rewriting history, does not
  un-leak a key someone may already have cloned. Only after independently verifying remediation, have an authorized maintainer review any proposed fingerprint suppression. An ignore entry itself proves neither revocation nor safety.
- **env:** add `.env` to `.gitignore`, and keep only placeholders in `.env.example`.

## Limitations

- **Pattern matching.** Some provider-shaped/high-entropy strings are detected; other secrets can be missed. A zero-match result is not a complete security assessment.
- **The hook is opt-in.** Each clone has to install it, and `git commit --no-verify` skips it. CI catches
  what slips through, but by then the key is on GitHub and must be revoked.
- **Nothing server-side.** Hook/CI operation is separate from platform branch and push protection. Configure the platform’s current access and protection policy independently.
- **Git only.** It does not scan PR descriptions, issues, Actions logs, forks, or files outside git.
- **dotenv only.** The ignore check knows `dotenv` and `.env` templates; other local config files
  (`secrets.yaml`, `config.local.json`) are covered only by the secret patterns.
- **One generic allowlist.** Short words joined by `-` or `/` (for example `a2-eval-suggestions`,
  `Claude/Anthropic`) are not reported by `generic-api-key`. This is retained historical tuning, not a newly reproduced measurement. Provider rules are unaffected.
- The GitHub Action installs the Linux x64 gitleaks binary (checksum pinned), so it needs an
  `ubuntu-*` runner.

## Current evidence and open decisions

[agent.yaml](agent.yaml) is a descriptive unconfirmed mandate; [AUDIT-CRITERIA.md](AUDIT-CRITERIA.md) links criteria to actual synthetic tests. [SECURITY.md](SECURITY.md) states the Git/ref/suppression and data boundaries. The suite preserves the original nine cases and adds index-vs-working-tree policy, local exclusions, Git/scanner failures, hook-path regressions and synthetic sweep aggregation. No real repository sweep, real key validation, model call or user-hook installation is part of these tests.

Quoted/control-character paths and unreadable policy are treated as incomplete. Index reads are not a concurrent transaction; keep the source/index stable. The optional sweep returns 2 for errors, missing selected input or no inspected repo; 1 for findings; 0 for completed clean scope. Its synthetic aggregation tests do not independently validate real repositories. Accepted owner/CODEOWNERS and repository license remain unresolved; no MIT or commercial-use grant is inferred.
