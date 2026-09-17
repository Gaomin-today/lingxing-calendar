#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift build --disable-sandbox --cache-path "$PWD/build/cache" --scratch-path "$PWD/build/swift"
PREVIEW_APP="$PWD/build/灵性日历预览.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
cp build/swift/debug/LingxingCalendar "$PREVIEW_APP/Contents/MacOS/LingxingCalendar.new"
mv -f "$PREVIEW_APP/Contents/MacOS/LingxingCalendar.new" "$PREVIEW_APP/Contents/MacOS/LingxingCalendar"
cp Resources/Info.plist "$PREVIEW_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$PREVIEW_APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.lingxing.calendar.preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 灵性日历预览' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 灵性日历预览' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LingxingPreviewDataFile string $PWD/build/preview-events.json" "$PREVIEW_APP/Contents/Info.plist"
if [[ ! -f build/preview-events.json ]]; then
python3 - <<'PY'
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import json, uuid
zone=ZoneInfo('Asia/Shanghai')
now=datetime.now(zone)
day=now.replace(hour=0,minute=0,second=0,microsecond=0)
reference=datetime(2001,1,1,tzinfo=ZoneInfo('UTC'))
def item(title,start,duration=60,task=False,due=True,completed=False):
    return dict(id=str(uuid.uuid4()),title=title,start=(start-reference).total_seconds(),end=(start+timedelta(minutes=duration)-reference).total_seconds(),notes='隔离预览的合成验收数据',isAllDay=False,repeatRule='none',isCompleted=completed,isTask=task,taskHasDueDate=due,taskDueHasTime=True)
rows=[item('预览 · 产品讨论',day+timedelta(hours=10),90),item('预览 · 面试准备',day+timedelta(hours=10,minutes=30),60),item('预览 · 散步',day+timedelta(hours=15),30),item('预览 · 跨日出行',day-timedelta(hours=1),150),item('预览 · 整理资料',day+timedelta(hours=18),0,True),item('预览 · 不设期限的阅读',day,0,True,False)]
json.dump(rows,open('build/preview-events.json','w'),ensure_ascii=False,indent=2)
PY
fi
codesign --force --deep --sign - "$PREVIEW_APP"
echo "隔离预览：$PREVIEW_APP（合成数据，不读取真实本地日程、不发通知）"
