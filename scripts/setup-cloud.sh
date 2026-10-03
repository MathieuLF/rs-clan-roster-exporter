#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Setup supports Ubuntu Linux x86_64.' >&2; exit 1; }
for tool in curl tar sha256sum python3 git; do command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }; done
eval "$(python3 - "$root/scripts/toolchain.json" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1]))
for name, key in [('ps_version','powershell'), ('ps_hash','powershellLinuxX64Sha256'), ('node_version','node'), ('node_hash','nodeLinuxX64Sha256')]:
    print(name + '=' + shlex.quote(d[key]))
PY
)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/rs-clan-roster-exporter"
bin="$HOME/.local/bin"
mkdir -p "$cache" "$bin"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
install_archive() {
    local name="$1" url="$2" hash="$3" destination="$4" strip="$5"
    if [[ ! -f "$destination/.archive-sha256" ]] || [[ "$(cat "$destination/.archive-sha256")" != "$hash" ]]; then
        curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 "$url" -o "$scratch/$name"
        printf '%s  %s\n' "$hash" "$scratch/$name" | sha256sum --check -
        mkdir -p "$destination"
        tar -xf "$scratch/$name" -C "$destination" --strip-components="$strip"
        printf '%s\n' "$hash" > "$destination/.archive-sha256"
    fi
}
install_archive powershell.tar.gz "https://github.com/PowerShell/PowerShell/releases/download/v$ps_version/powershell-$ps_version-linux-x64.tar.gz" "$ps_hash" "$cache/powershell-$ps_version" 0
chmod +x "$cache/powershell-$ps_version/pwsh"
ln -sfn "$cache/powershell-$ps_version/pwsh" "$bin/pwsh"
install_archive node.tar.xz "https://nodejs.org/dist/v$node_version/node-v$node_version-linux-x64.tar.xz" "$node_hash" "$cache/node-$node_version" 1
ln -sfn "$cache/node-$node_version/bin/node" "$bin/node"
export PATH="$bin:$PATH"
pwsh -NoProfile -NonInteractive -File "$root/scripts/Setup-Tools.ps1"
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
node --version
echo 'Setup ready. Use PATH=$HOME/.local/bin:$PATH in Cloud environment settings or invoke ~/.local/bin/pwsh explicitly.'
