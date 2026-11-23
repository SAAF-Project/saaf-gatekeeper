#!/usr/bin/env bash
# Shared Linux CI/action installer; checks the pinned release before execution.
set -euo pipefail
destination="${1:?give an isolated installation directory}"
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
  echo 'gatekeeper installer requires Linux x86_64' >&2
  exit 2
fi
mkdir -p "$destination"
download="$(mktemp -d "$destination/.download.XXXXXX")"
trap 'rm -rf "$download"' EXIT
curl --fail --silent --show-error --location -o "$download/gitleaks.tgz" \
  https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
echo "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  $download/gitleaks.tgz" | sha256sum -c -
tar -xzf "$download/gitleaks.tgz" -C "$download" gitleaks
install -m 755 "$download/gitleaks" "$destination/gitleaks"
"$destination/gitleaks" version
