#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swift-module-cache"
swift build -c release --scratch-path .build --cache-path .build/cache
binary_dir="$(swift build -c release --scratch-path .build --cache-path .build/cache --show-bin-path)"
mkdir -p "$project_dir/dist"
build_root="$(mktemp -d "$project_dir/dist/.codex-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
app_dir="$build_root/Codex用量.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/CodexMenuBar" "$app_dir/Contents/MacOS/CodexMenuBar"
# Keep the unstripped original in .build for diagnostics; strip only the copy
# shipped in the app, before signing. Runtime reflection metadata is retained.
xcrun strip -S -x "$app_dir/Contents/MacOS/CodexMenuBar"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
mkdir -p "$app_dir/Contents/Resources/Coffee"
cp "$project_dir/Resources/Coffee/full.jpg" "$project_dir/Resources/Coffee/empty.jpg" "$project_dir/Resources/Coffee/steam.png" "$app_dir/Contents/Resources/Coffee/"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
# Never truncate an executable that a running process may still have mapped.
# Install a complete, verified bundle by renaming; restore the old bundle on failure.
python3 - "$app_dir" "$project_dir/dist/Codex用量.app" "$build_root/previous.app" <<'PY'
from pathlib import Path
import sys
staged, target, previous = map(Path, sys.argv[1:])
if target.exists():
    target.rename(previous)
try:
    staged.rename(target)
except BaseException:
    if previous.exists():
        previous.rename(target)
    raise
PY
printf '已编译并签名：%s\n' "$project_dir/dist/Codex用量.app"
