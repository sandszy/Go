---
name: ui-tests-duo
description: 跑登登围棋的 UI 测试（iPhone Duo 模拟器）。改界面、布局或提示后，需要验证横屏、竖屏布局时用这个 skill；一条命令会自动转屏、横竖各跑一遍。
---

# 登登围棋 UI 测试（iPhone Duo）

项目规则：模拟器一律用 iPhone Duo，不要新建 iPad 模拟器（见 CLAUDE.md）。

## 一键跑

```bash
Scripts/ui-tests-duo.sh
```

脚本会：读当前内屏方向 → 跑一遍完整 UI 测试 → 用 DeviceHub 的旋转快捷键（⌘←）转一次屏 → 再跑一遍 → 打印两遍的通过/失败/跳过。任何一遍有失败，退出码非 0。

需要：DeviceHub 能打开；运行脚本的终端有「辅助功能」权限（第一次会弹授权）。

## 结果怎么读

每遍是 **4 过、2 跳过**：跳过的是「另一个方向的布局」和「横屏原图不用滚动」。两遍合起来 6 条用例都跑到。

- `testReferenceImageVisibleInLandscape` 是 iPad 的界面原则（技术架构第 8 节），在 Duo 上永远跳过；等真机 iPad mini 在手边时再验证，不要在手机上放宽这条。
- 截图附件用 `app.screenshot()` 抓的是 App 窗口；`XCUIScreen.main` 在 Duo 上可能抓到另一块屏，是黑的。

## 别踩的坑

- Duo 的系统**不允许代码转屏**：`XCUIDevice.shared.orientation` 只改方向标记，`UIWindowScene.requestGeometryUpdate` 返回 `UISceneErrorDomain` 101「当前窗口模式不允许以编程方式更改界面方向」。不要为转屏给 App 加测试钩子，没用。
- 只有 DeviceHub 的旋转快捷键（⌘←/⌘→）能把内屏转过去，脚本已经处理。
- 界面测试里判断当前方向用 `app.windows.firstMatch.frame` 的宽高；屏幕真转过以后这个值是可靠的。
- 先跑单元测试再跑 UI：`cd GoKit && swift test`。

## 脚本坏了时的兜底

```bash
xcodebuild test -project DengDengGo.xcodeproj -scheme DengDengGo \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/dd
```

在 DeviceHub 里把模拟器转到横屏跑一次，再转到竖屏跑一次，各自看结果。
