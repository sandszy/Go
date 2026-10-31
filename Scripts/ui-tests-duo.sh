#!/usr/bin/env bash
# 在 iPhone Duo 上跑 UI 测试：转一次屏，横竖两个方向各跑一遍，结果汇总。
# 为什么：Duo 的系统不允许代码更改界面方向（UISceneErrorDomain 101），XCUIDevice 也不管用；
# 只有 DeviceHub 的旋转快捷键能把内屏转过去。
set -euo pipefail
cd "$(dirname "$0")/.."

device="iPhone Duo"
shot="/tmp/duo-ui-test-screen-$$.png"
trap 'rm -f "$shot"' EXIT

udid=$(xcrun simctl list devices available | grep "$device (" | sed -E 's/.*\(([-0-9A-F-]{36})\).*/\1/' | head -1)
if [ -z "$udid" ]; then
    echo "找不到 $device 模拟器，先在 Xcode 里建一台。" >&2
    exit 1
fi

open -a "/Applications/Xcode.app/Contents/Applications/DeviceHub.app" 2>/dev/null || true
sleep 2

screenshot() {
    xcrun simctl io "$udid" screenshot --display=3 "$shot" >/dev/null 2>&1 \
        || xcrun simctl io "$udid" screenshot "$shot" >/dev/null 2>&1
}

# 内屏截图的长宽比就是当前方向：横屏宽比高大，竖屏反过来。
orientation() {
    screenshot
    width=$(sips -g pixelWidth "$shot" 2>/dev/null | awk '/pixelWidth/{print $2}')
    height=$(sips -g pixelHeight "$shot" 2>/dev/null | awk '/pixelHeight/{print $2}')
    if [ "${width:-0}" -gt "${height:-0}" ]; then echo landscape; else echo portrait; fi
}

rotate() {
    osascript -e 'tell application "DeviceHub" to activate' >/dev/null
    sleep 1
    osascript -e 'tell application "System Events" to key code 123 using command down' >/dev/null
    sleep 3
}

run_pass() {
    label=$1
    log="/tmp/duo-ui-tests-$label.log"
    echo "== $label =="
    xcodebuild test -project DengDengGo.xcodeproj -scheme DengDengGo \
        -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/dd >"$log" 2>&1 || true
    result=$(ls -td build/dd/Logs/Test/*.xcresult | head -1)
    xcrun xcresulttool get test-results summary --path "$result" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
print("通过 %d，失败 %d，跳过 %d" % (d["passedTests"], d["failedTests"], d["skippedTests"]))
for f in d.get("testFailures", []):
    print("- %s：%s" % (f.get("testName"), f.get("failureText")))
sys.exit(1 if d["failedTests"] else 0)
'
}

status=0
first=$(orientation)
echo "第一遍：$first"
run_pass "$first" || status=1

rotate
second=$(orientation)
if [ "$second" = "$first" ]; then
    echo "转屏没生效（还是 $second）。确认 DeviceHub 在前台，终端有辅助功能权限。" >&2
    exit 1
fi
echo "第二遍：$second"
run_pass "$second" || status=1

exit $status
