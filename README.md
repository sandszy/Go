# 登登围棋

以 iPad 为主的围棋学习 App：拍下印刷的作业题，摆上棋盘自己做，卡住时分级提示。

## 目录

- `DengDengGo.xcodeproj`、`DengDengGo/`：iOS App 外壳：入口、资源，以及 `Engine/` 里把 KataGo 接进 App 的代码和配置。
- `GoKit/`：Swift 包，主要代码都在这里。
  - `GoCore`：规则引擎（提子、禁入点、打劫）、题目模型、变化树、入门题判题，以及用 KataGo 判题（死活外框、按目数判对错），纯 Swift。
  - `GoVision`：从照片识别印刷习题：找棋盘图、认黑白子、读“黑先”、题型、题号和页码。
  - `GoUI`：棋盘和摆题、做题界面，iOS 和 macOS 都能编译。
  - `board-snapshot`：把棋盘渲染成 PNG，没有模拟器时检查画面用。
- `ThirdParty/KataGo/`：KataGo v1.16.4 源码里 App 用得到的部分（MIT 许可，见其中的 `LICENSE`），包括 Metal（GPU）和 Eigen（CPU）两个后端。`neuralnet/eigenbackend.cpp` 为了在苹果芯片上提速改过几处，都标了“登登围棋改动”。
- `ThirdParty/KataGoBridge/`：在 App 进程里跑 KataGo 分析引擎的 Objective-C++ 桥，以及运行时在两个后端之间转发的 `KataGoBackend.cpp`。
- `ThirdParty/Eigen/`：Eigen 3.4.0 矩阵库的头文件（MPL2 许可），CPU 后端用。

## 判题引擎（KataGo）

做题时用本地的 KataGo 判对错、替对方应，不用联网。没打包模型时退回入门判题器（只会吃子、逃子、对杀）。

- **GPU 还是 CPU 自动选**：有能用的 GPU 就用 Metal（GPU），模拟器里自动换成 Eigen（CPU）——模拟器的虚拟 GPU 不支持 Metal 后端用的 MPSGraph，一算就崩。摆题页“题目目标”下面的灰字会写“判题：KataGo（GPU）……”或“KataGo（CPU）”。
- **启动参数**：`-katagoHardware gpu` / `cpu` 强制用某一个，`off` 不用引擎（UI 测试用这个，判题快、结果固定）。在 Xcode 里是 Product → Scheme → Edit Scheme → Run → Arguments。
- **模型不在仓库里**（约 98MB），第一次编译前先下载：

  ```bash
  Scripts/fetch-katago-model.sh
  ```

  下载到 `DengDengGo/Engine/kata1-b18c384nbt.bin.gz`，编译时自动打包进 App。KataGo 的模型按 KataGo Neural Network License 发布，可以随 App 分发，但要附上版权和许可声明；上架前要在 App 里加一个“致谢”页，放 KataGo 和模型的许可。
- **CPU 慢得多**：在 Mac 的模拟器里每秒约 8 次（iPad mini 的 GPU 约 60 次），开头的分析要一分多钟，下完一手判出结果要几十秒。只适合开发时在模拟器里试流程，给孩子用要装到真 iPad 上。第 35 页 6 道题 CPU 和 GPU 的答案一致。
- **怎么判**：题目外面摆上都活净的外框，让全盘输赢只取决于题目这一块（日本规则数目）；孩子每一手比引擎认为最好的一手亏 1.5 目以上就算错。题目开头比较“做题方先下”和“做题方停一手”，归属变化大的子就是要分死活的子。
- **一直下到结果摆在棋盘上**：有要吃掉的对方子时，要真的提掉才判“答对了”；没有要吃的子（做活等），要分死活的子都定下来、对方没有要紧的手了才算完。中间孩子每一手都判，对方由 AI 应；第一手以后双方只在要分死活的那几块棋旁边下。下对 15 手还没完也算答对。
- **下到题目外面**：引擎那边题目区域外是外框，下在那里直接判错，提示可以悔棋，后面不再判，悔掉那手再接着判。对杀题的区域只到棋子外面一路，比印出来的图小时，提示“离题目里的棋子太远了”。
- **AI 陪下开关**：做题页上随时开关。关掉自己两边下；再打开，AI 从眼前的局面接着判、接着应。有 KataGo 时答错以后也能接着陪下（可以悔棋，也可以接着下）。
- **外框的颜色**：吃子、逃子、做活、杀棋题按题目要谁跑出去定一种颜色；对杀和没设目标的题，每条边用离那条边最近的子的颜色（比如上边黑、右边白），双方在外面的子都算活的。搜索时双方都不下离棋子两路以外的空点，免得引擎去外框交界处占地。
- **思考深度**：“AI 陪下”下面可以选“快 / 标准 / 深”，每个局面分别算 100 / 200 / 400 次，不限时间，算满为止；选了以后下次打开还是这一档，中途改从下一手开始用。
- **GPU 的速度**：iPad mini（A17 Pro）上每秒大约算 50 次，换线程数、批大小都快不了，是这个模型（b18c384）本身就大。进入做题后就在后台算，孩子想的时候先算好眼前的局面，再猜孩子最可能下的 3 手提前算好：猜中了下完马上应，猜错了别的猜测立刻停下，让给要算的那一手。对方应手前至少停 0.3 秒，引擎算的时间也算在里面。
  - 自测里每手只想 2 秒，第 35～37 页 19 道题，孩子下完到对方应手：快档中位 0.8 秒（六成多在 1 秒内），标准档中位 2.4 秒，深档中位 6.8 秒；孩子想得越久，猜中、算完的越多，等得越短。
- **自测**：用 `-engineSelfTest <照片路径>` 启动，会打印用的是 GPU 还是 CPU、每秒算多少次，以及每道题引擎找到的正解、用时和每手等了多久。加 `-engineDepth quick|standard|deep` 选档位；`-engineSpeedOnly` 只测速度；`-katagoConfig "参数=值, 参数=值"` 临时改 KataGo 配置（只在调试版里有）。模拟器里直接传 Mac 上照片的绝对路径；真机上先把照片拷进 App 的 Documents：

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
3. 选一个 iPad 模拟器，运行。

## 测试

```bash
cd GoKit && swift test
```

只装了命令行工具、没有 Xcode 时，找不到测试宏插件，要加上插件路径：

```bash
cd GoKit && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

识别测试有两部分：一部分用程序画的棋谱图，随时能跑；另一部分读真实的作业照片。照片是孩子的作业，不进仓库（见 `.gitignore`），放在仓库根目录的 `棋盘照片样例/` 或 `Samples/` 文件夹里时才会测：已知内容的几张逐子核对，其余的打印识别结果供人工对照。新拍的照片放进去就会跑。

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
