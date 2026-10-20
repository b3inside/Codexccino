#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swift-module-cache"
swiftc_path="$(xcrun --find swiftc)"
testing_plugins="$(dirname "$swiftc_path")/../lib/swift/host/plugins/testing"
extra_flags=()
if [[ -f "$testing_plugins/libTestingMacros.dylib" ]]; then
    extra_flags=(-Xswiftc -plugin-path -Xswiftc "$testing_plugins")
fi
swift test --disable-xctest --scratch-path .build --cache-path .build/cache "${extra_flags[@]}"
