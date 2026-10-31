# 登登围棋

以 iPad 为主的围棋学习 App：拍下印刷的作业题，摆上棋盘自己做，AI 给每一手打分、替对手应；也可以在空棋盘上和 AI 下一整盘，下完按按钮数子。

## 目录

- `docs/`：需求说明和技术架构，见下面的“文档”。
- `DengDengGo.xcodeproj`、`DengDengGo/`：iOS App 外壳：入口、资源，以及 `Engine/` 里把 KataGo 接进 App 的代码和配置。
- `GoKit/`：Swift 包，主要代码都在这里。
  - `GoCore`：规则引擎（提子、禁入点、打劫）、题目模型、变化树，以及用 KataGo 给每一手打分（死活外框、比最好的一手亏几目）、对弈时选手和数子，纯 Swift。
  - `GoVision`：从照片识别印刷习题：找棋盘图、认黑白子、读“黑先”、题型、题号和页码。
  - `GoUI`：棋盘和摆题、做题界面，iOS 和 macOS 都能编译。
  - `board-snapshot`：把棋盘渲染成 PNG，没有模拟器时检查画面用。
- `ThirdParty/KataGo/`：KataGo v1.16.4 源码里 App 用得到的部分（MIT 许可，见其中的 `LICENSE`），包括 Metal（GPU）和 Eigen（CPU）两个后端。`neuralnet/eigenbackend.cpp` 为了在苹果芯片上提速改过几处，都标了“登登围棋改动”。
- `ThirdParty/KataGoBridge/`：在 App 进程里跑 KataGo 分析引擎的 Objective-C++ 桥，以及运行时在两个后端之间转发的 `KataGoBackend.cpp`。
- `ThirdParty/Eigen/`：Eigen 3.4.0 矩阵库的头文件（MPL2 许可），CPU 后端用。

## 文档

- [需求说明](docs/需求说明.md)：App 现在怎么用、怎么算做对，每条带验收标准和对应的测试；还有“还没做”的清单。
- [技术架构](docs/技术架构.md)：模块、数据、关键流程、存储格式、启动参数和架构决策。
- [CLAUDE.md](CLAUDE.md)：开发流程。改行为先改需求说明，再写代码。

## KataGo 模型

做题时用本地的 KataGo 给每一手打分、替对方应，不用联网。模型不在仓库里（约 98MB），第一次编译前先下载：

```bash
Scripts/fetch-katago-model.sh
```

下载到 `DengDengGo/Engine/kata1-b18c384nbt.bin.gz`，编译时自动打包进 App。没有模型时 App 照样能编译，只是不打分。KataGo 的模型按 KataGo Neural Network License 发布，可以随 App 分发，但要附上版权和许可声明；上架前要在 App 里加一个“致谢”页，放 KataGo 和模型的许可。

启动参数（`-katagoHardware`、`-engineSelfTest` 等）见[技术架构](docs/技术架构.md#6-构建运行和测试)。在 Xcode 里是 Product → Scheme → Edit Scheme → Run → Arguments。

真机自测时先把照片拷进 App 的 Documents，再带 `-engineSelfTest` 启动：

```bash
xcrun devicectl device copy to --device <iPad 的 UDID> --domain-type appDataContainer --domain-identifier com.sandszy.dengdenggo --source 棋盘照片样例/棋盘照片样例.HEIC --destination Documents/sample.heic
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
3. 选 iPhone Duo 模拟器，运行。

## 测试

```bash
cd GoKit && swift test
```

只装了命令行工具、没有 Xcode 时，找不到测试宏插件，要加上插件路径：

```bash
cd GoKit && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

识别测试有两部分：一部分用程序画的棋谱图，随时能跑；另一部分读真实的作业照片。照片是孩子的作业，不进仓库（见 `.gitignore`），放在仓库根目录的 `棋盘照片样例/` 或 `Samples/` 文件夹里时才会测：已知内容的几张逐子核对，其余的打印识别结果供人工对照。新拍的照片放进去就会跑。

界面布局的 UI 测试（横屏、竖屏、提示位置）在 iPhone Duo 模拟器上跑，截图会存进测试结果。Duo 的系统不允许代码转屏，用这个脚本：它会打开 DeviceHub、转一次屏，横竖两个方向各跑一遍再汇总（终端需要辅助功能权限）。每次只验当前方向的那条布局，另一条跳过；横屏原图不用滚动是 iPad 的界面原则，手机上跳过：

```bash
Scripts/ui-tests-duo.sh
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

模拟器上用鼠标点就相当于用手指点。模拟器里 KataGo 跑在 CPU 上，算一手要几十秒，只适合试流程。

**方法二：装到真 iPad 上给登登用（推荐）**

第一次装到一台新 iPad 上，按下面的顺序做：

1. 用数据线把 iPad 连到 Mac，iPad 上弹出“要信任此电脑吗”时点信任。
2. 在 iPad 上打开“设置 → 隐私与安全性 → 开发者模式”，打开后 iPad 会重启。
3. 在 Xcode 的设置里打开 Accounts，用你的 Apple ID 登录。
4. 在 Xcode 里选中 DengDengGo 目标，打开 Signing & Capabilities，Team 选你的个人团队。如果提示 Bundle ID 已被占用，把 `com.sandszy.dengdenggo` 改一个别人没用过的名字。
5. 运行目标选你的 iPad，然后点运行。第一次装好后，在 iPad 上打开“设置 → 通用 → VPN 与设备管理”，信任你的开发者证书。
