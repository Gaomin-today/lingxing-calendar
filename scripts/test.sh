#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
DEV_PATH="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEV_PATH/Library/Developer/Frameworks"
ARGS=(--disable-sandbox --cache-path "$PWD/build/cache" --scratch-path "$PWD/build/swift" --disable-xctest --enable-swift-testing)
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    ARGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS")
    ARGS+=(-Xswiftc -plugin-path -Xswiftc "$DEV_PATH/usr/lib/swift/host/plugins/testing")
    ARGS+=(-Xlinker -F -Xlinker "$TEST_FRAMEWORKS")
    ARGS+=(-Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS")
    ARGS+=(-Xlinker -rpath -Xlinker "$DEV_PATH/Library/Developer/usr/lib")
fi
swift test "${ARGS[@]}"
