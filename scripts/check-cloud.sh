#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
profile="${1:-Dev}"
[[ $# -le 1 && ( "$profile" == Dev || "$profile" == Full ) ]] || { echo 'Usage: bash scripts/check-cloud.sh [Dev|Full]' >&2; exit 1; }
exec pwsh -NoProfile -NonInteractive -File "$root/scripts/Test-Local.ps1" -Profile "$profile"
