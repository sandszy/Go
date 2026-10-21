# 登登围棋

以 iPad 为主的围棋学习 App：拍下印刷的作业题，摆上棋盘自己做，卡住时分级提示。

## 目录

- `DengDengGo.xcodeproj`、`DengDengGo/`：iOS App 外壳：入口、资源，以及 `Engine/` 里把 KataGo 接进 App 的代码和配置。
- `GoKit/`：Swift 包，主要代码都在这里。
  - `GoCore`：规则引擎（提子、禁入点、打劫）、题目模型、变化树、入门题判题，以及用 KataGo 判题（死活外框、按目数判对错），纯 Swift。
  - `GoVision`：从照片识别印刷习题：找棋盘图、认黑白子、读“黑先”、题型、题号和页码。
  - `GoUI`：棋盘和摆题、做题界面，iOS 和 macOS 都能编译。
  - `board-snapshot`：把棋盘渲染成 PNG，没有模拟器时检查画面用。
- `ThirdParty/KataGo/`：KataGo v1.16.4 源码里 App 用得到的部分（MIT 许可，见其中的 `LICENSE`），用 Metal 后端。
- `ThirdParty/KataGoBridge/`：在 App 进程里跑 KataGo 分析引擎的 Objective-C++ 桥。

## 判题引擎（KataGo）

做题时用本地的 KataGo 判对错、替对方应，不用联网。没打包模型、或者在模拟器上时，退回入门判题器（只会吃子、逃子、对杀）。

- **模型不在仓库里**（约 98MB），第一次编译前先下载：

  ```bash
  Scripts/fetch-katago-model.sh
  ```

  下载到 `DengDengGo/Engine/kata1-b18c384nbt.bin.gz`，编译时自动打包进 App。KataGo 的模型按 KataGo Neural Network License 发布，可以随 App 分发，但要附上版权和许可声明；上架前要在 App 里加一个“致谢”页，放 KataGo 和模型的许可。
- **模拟器上不跑引擎**：模拟器的虚拟 GPU 不支持 KataGo Metal 后端用的 MPSGraph，一算就崩。要试引擎得装到真 iPad 上。
- **怎么判**：题目外面摆上两色都活净的外框，让全盘输赢只取决于题目这一块；孩子这一手比引擎认为最好的一手亏 1.5 目以上就算错。题目开头比较“做题方先下”和“做题方停一手”，归属变化大的子就是要分死活的子，这些子都倒向做题方时算做完。
- **速度**：iPad mini（A17 Pro）上每个局面算 400 次，开头的分析要 10 秒左右，进入做题后就在后台算，孩子想的时候已经算好；下完一手到判出结果一般 1～4 秒。
- **在真机上自测**：把作业照片拷进 App 的 Documents，用 `-engineSelfTest` 参数启动，会打印每道题引擎找到的正解和用时：

  ```bash
  xcrun devicectl device copy to --device <iPad 的 UDID> --domain-type appDataContainer --domain-identifier com.sandszy.dengdenggo --source 棋盘照片样例.HEIC --destination Documents/sample.heic
  ```

  ```bash
  xcrun devicectl device process launch --device <iPad 的 UDID> --console --terminate-existing com.sandszy.dengdenggo -- -engineSelfTest sample.heic
  ```

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
xcodebuild test -project DengDengGo.xcodeproj -scheme DengDengGo -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)'
```

## 渲染棋盘

```bash
cd GoKit && swift run board-snapshot /tmp/snapshots
```

## 怎么试

**方法一：在 Mac 上用模拟器，现在就能试**

1. 用 Xcode 打开 `DengDengGo.xcodeproj`。
2. 在顶部的运行目标里选一台 iPad 模拟器，比如 “iPad Air 11-inch (M4)”。
3. 点运行（⌘R）。

模拟器上用鼠标点就相当于用手指点。模拟器里不跑 KataGo，判题用的是入门判题器。

**方法二：装到真 iPad 上给登登用（推荐）**

我刚查了一下，这台 Mac 上还没连接真 iPad，Xcode 里也还没登录 Apple ID。按下面的顺序做：

1. 用数据线把 iPad 连到 Mac，iPad 上弹出“要信任此电脑吗”时点信任。
2. 在 iPad 上打开“设置 → 隐私与安全性 → 开发者模式”，打开后 iPad 会重启。
3. 在 Xcode 的设置里打开 Accounts，用你的 Apple ID 登录。
4. 在 Xcode 里选中 DengDengGo 目标，打开 Signing & Capabilities，Team 选你的个人团队。如果提示 Bundle ID 已被占用，把 `com.sandszy.dengdenggo` 改一个别人没用过的名字。
5. 运行目标选你的 iPad，然后点运行。第一次装好后，在 iPad 上打开“设置 → 通用 → VPN 与设备管理”，信任你的开发者证书。
