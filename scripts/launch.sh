#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$project_dir/dist/Codex用量.app}"
# Let Launch Services own the app lifetime instead of a terminal/tool session.
open -a "$app_dir"
