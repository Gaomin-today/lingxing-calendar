#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# Reuse a completed debug Core build when available. A clean CI checkout builds
# only Core in its own temporary scratch directory. Neither path writes to the
# application's shared Swift scratch directory or touches actual user profiles.
CHECKS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lingxi-profile-checks.XXXXXX")"
trap 'rm -rf "$CHECKS_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$CHECKS_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CHECKS_DIR/ModuleCache"
CORE_BIN="${LINGXI_CORE_BIN:-$PWD/build/swift/debug}"
if [[ ! -f "$CORE_BIN/Modules/LingxiCore.swiftmodule" || ! -d "$CORE_BIN/LingxiCore.build" || ! -d "$CORE_BIN/LunarSwift.build" ]]; then
    if [[ -n "${LINGXI_CORE_BIN:-}" ]]; then
        print -u2 "LINGXI_CORE_BIN 需要指向含 LingxiCore 与 LunarSwift 模块和对象文件的 Debug 构建。"
        exit 2
    fi
    BUILD_ARGS=(--disable-sandbox --cache-path "$CHECKS_DIR/cache" --scratch-path "$CHECKS_DIR/swift")
    swift build "${BUILD_ARGS[@]}" --target LingxiCore
    CORE_BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
fi
CORE_OBJECTS=("$CORE_BIN"/LingxiCore.build/*.swift.o)
LUNAR_OBJECTS=("$CORE_BIN"/LunarSwift.build/*.swift.o)

swiftc -swift-version 5 -parse-as-library \
    -module-name BirthProfileStoreChecks \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    -I "$CORE_BIN/Modules" \
    Sources/LingxiApp/BirthProfileStore.swift \
    Tests/SystemIntegrationChecks/BirthProfileStoreChecks.swift \
    "${CORE_OBJECTS[@]}" \
    "${LUNAR_OBJECTS[@]}" \
    -o "$CHECKS_DIR/BirthProfileStoreChecks"

"$CHECKS_DIR/BirthProfileStoreChecks"
