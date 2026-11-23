# Gatekeeper criteria and evidence

This proposal supplements the nine existing repository standards. It does not
approve a new norm, a license, an owner or a production merge policy. Unexecuted
controls remain **not assessed**; `agent.yaml` remains unconfirmed.

Run `bash tests/run.sh` with the reviewed Gitleaks 8.30.1 binary on PATH. Record
the guard commit, scanner version, OS/Bash version and CI run URL. CI uses pinned
Actions, read permissions and a checksum-verified dependency download; all scans
in the suite are synthetic, isolated local repositories.

| ID | Criterion | Evidence / boundary |
|---|---|---|
| GK-01 [code] | Clean fixtures pass; synthetic secrets deleted later or present on another local branch still fail. | Original `tests/run.sh` cases using generated fake keys; no real credential liveness test. |
| GK-02 [code] | Tracked env files and missing shared dotenv ignore policy fail; ordinary identifier text does not become a secret finding. | Original tracked-env/dotenv/allowlist fixtures. Rule tuning remains heuristic. |
| GK-03 [code] | Staged keys fail, clean staged input passes, shallow history is refused. | Original pre-commit and shallow-clone cases. All local refs are not every remote/fork. |
| GK-04 [code] | Indexed ignore policy decides staged safety; unstaged `.gitignore` changes and local excludes cannot hide its removal. | Paired staged/unstaged tests and local-exclude negative fixture. Concurrent index mutation is not prevented. |
| GK-05 [code] | Failed path enumeration/grep and Gitleaks setup failure remain exit 2, even if a partial report contains findings. | Command-failure wrappers around real temporary Git state; no clean fallback. |
| GK-06 [code] | Existing hook symlinks are preserved; generated hooks retain a literal tool path containing shell characters. | Temporary hook-installation fixtures only; no user hook is installed by CI or this batch. |
| GK-07 [code] | Test output never contains the generated fake credential value. | Every selftest checks redaction. This does not prove all possible metadata or secret formats are absent. |
| GK-09 [code] | The optional sweep preserves findings/error statuses and refuses a missing explicitly selected repository. | Synthetic temporary repo plus a stub scanner; no live sweep. Empty/incomplete scope exits 2, findings exit 1, completed clean scope exits 0. |
| GK-08 [human] | An authorized maintainer verifies remediation, suppression scope, repository rights, access and final checker pins. | **Not assessed**: owner/CODEOWNERS and license are unresolved; no actual key revocation or history rewrite performed. |

No LLM criterion is applicable to the deterministic guard; no model behavior or
independent assurance is claimed. Historical repo anecdotes are not current-head
test evidence. The consumer example remains pinned to an earlier main revision;
new candidate fixes require a separately reviewed repin before consumer adoption.
