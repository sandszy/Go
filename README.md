# 登登围棋

以 iPad 为主的围棋学习 App：拍下印刷的作业题，摆上棋盘自己做，卡住时分级提示。

## 目录

- `DengDengGo.xcodeproj`、`DengDengGo/`：iOS App 外壳，只有入口和资源。
- `GoKit/`：Swift 包，主要代码都在这里。
  - `GoCore`：规则引擎（提子、禁入点、打劫）和题目模型，纯 Swift。
  - `GoUI`：棋盘和摆题、做题界面，iOS 和 macOS 都能编译。
  - `board-snapshot`：把棋盘渲染成 PNG，没有模拟器时检查画面用。

## 第一次用 Xcode 打开

1. 装好 Xcode 后，让命令行也用它：

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. 打开 `DengDengGo.xcodeproj`，在 Signing & Capabilities 里选你的开发者团队。Bundle ID 暂时是 `com.sandszy.dengdenggo`，可以改。
3. 选一个 iPad 模拟器，运行。

## 测试

```bash
cd GoKit && swift test
```

只装了命令行工具、没有 Xcode 时，找不到测试宏插件，要加上插件路径：

```bash
cd GoKit && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

界面布局的 UI 测试（横屏、竖屏、提示位置）在 iPad 模拟器上跑，截图会存进测试结果：

```bash
xcodebuild test -project DengDengGo.xcodeproj -scheme DengDengGo -destination 'platform=iOS Simulator,name=iPad (A16)'
```

## 渲染棋盘

```bash
cd GoKit && swift run board-snapshot /tmp/snapshots
```
