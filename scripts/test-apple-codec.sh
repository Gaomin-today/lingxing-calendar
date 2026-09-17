#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# Compile the real EventKit bridge, but execute only its pure date codec.
# No SystemCalendarService or EKEventStore is instantiated by these checks.
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
CHECKS_DIR="$PWD/build/apple-codec-checks"
mkdir -p "$CHECKS_DIR"
BUILD_ARGS=(--disable-sandbox --cache-path "$PWD/build/cache" --scratch-path "$CHECKS_DIR/swift")
swift build "${BUILD_ARGS[@]}" --target LingxiCore
CORE_BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
CORE_OBJECTS=("$CORE_BIN"/LingxiCore.build/*.swift.o)
LUNAR_OBJECTS=("$CORE_BIN"/LunarSwift.build/*.swift.o)

swiftc -swift-version 5 -parse-as-library \
    -module-name ReminderDateCodecChecks \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    -I "$CORE_BIN/Modules" \
    Sources/LingxiApp/SystemCalendarService.swift \
    Tests/SystemIntegrationChecks/ReminderDateCodecChecks.swift \
    "${CORE_OBJECTS[@]}" \
    "${LUNAR_OBJECTS[@]}" \
    -o "$CHECKS_DIR/ReminderDateCodecChecks"

"$CHECKS_DIR/ReminderDateCodecChecks"
