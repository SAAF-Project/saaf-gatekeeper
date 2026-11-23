# Security boundary

Gatekeeper is a local Git/Gitleaks guard, not a key-validation service or a
complete data-loss prevention system. Pattern matches are candidate findings.
The scanner never tests credentials against their providers. No model is used.

Report a vulnerability through private vulnerability reporting if enabled, or
an existing trusted private maintainer channel. Never paste key values or
unverified private-repo findings into public issues. Accepted ownership, a
dedicated contact and a response SLA remain open.

The guard uses its own configuration and redacted report template. Secret
suppression fingerprints are still read from the target repository; they need
independent review and do not establish revocation. A candidate PR cannot approve
its own checker/policy update merely by changing its tests or ignore file.

The dotenv policy is taken from the index, with ordinary `.gitignore` blobs
copied into a temporary Git repo. Unstaged changes, `.git/info/exclude` and global
excludes cannot stand in for shared policy. Quoted/control-character paths and
unreadable Git state are refused. This is not a transaction across concurrent
index changes; run the check against a stable checkout/index.

Full-history mode requires a complete clone, but `--all` means locally available
refs, not every fork, remote or deleted unreachable object. Hooks are optional
and can be bypassed. CI detects after a push and can be disabled; branch/push
protection needs a separately configured platform policy.

The Action installer downloads only the pinned Gitleaks release and verifies its
SHA256 before execution. It requires Linux x86_64 and installation network
access. The tests themselves use temporary repositories and generated fake keys;
they do not run the sweep over real repositories. Local hook installation changes
only an explicitly requested target and refuses an existing hook, including a
dangling symlink. Existing hook directories or Git configuration still require
operator trust. A repository license has not yet been established.
