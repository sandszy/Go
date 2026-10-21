# 登登围棋

以 iPad 为主的围棋学习 App：拍下印刷的作业题，摆上棋盘自己做，卡住时分级提示。

## 目录

- `DengDengGo.xcodeproj`、`DengDengGo/`：iOS App 外壳，只有入口和资源。
- `GoKit/`：Swift 包，主要代码都在这里。
  - `GoCore`：规则引擎（提子、禁入点、打劫）、题目模型、变化树和入门题判题，纯 Swift。
  - `GoVision`：从照片识别印刷习题：找棋盘图、认黑白子、读“黑先”、题型、题号和页码。
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

识别测试有两部分：一部分用程序画的棋谱图，随时能跑；另一部分读真实的作业照片。照片是孩子的作业，不进仓库（见 `.gitignore`），放在仓库根目录的 `棋盘照片样例.HEIC` 或 `Samples/` 下时才会测。

界面布局的 UI 测试（横屏、竖屏、提示位置）在 iPad 模拟器上跑，截图会存进测试结果：

```bash
xcodebuild test -project DengDengGo.xcodeproj -scheme DengDengGo -destination 'platform=iOS Simulator,name=iPad (A16)'
```

## 渲染棋盘

```bash
cd GoKit && swift run board-snapshot /tmp/snapshots
```
