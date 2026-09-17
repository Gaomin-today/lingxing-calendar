#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift build --disable-sandbox --cache-path "$PWD/build/cache" --configuration release --scratch-path "$PWD/build/swift"
APP="$PWD/build/灵性日历.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/swift/release/LingxingCalendar "$APP/Contents/MacOS/LingxingCalendar.new"
mv -f "$APP/Contents/MacOS/LingxingCalendar.new" "$APP/Contents/MacOS/LingxingCalendar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
echo "已构建：$APP"
