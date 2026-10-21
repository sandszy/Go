// swift-tools-version: 6.0
import PackageDescription

/// 判题搜索和图像识别要处理大量数据，不开优化时慢上百倍，所以调试时也开优化。
let optimizedInDebug: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]

let package = Package(
    name: "GoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoCore", targets: ["GoCore"]),
        .library(name: "GoVision", targets: ["GoVision"]),
        .library(name: "GoUI", targets: ["GoUI"]),
    ],
    targets: [
        // 规则引擎、题目模型和判题，纯 Swift，不依赖界面。
        .target(name: "GoCore", swiftSettings: optimizedInDebug),
        // 从照片里识别印刷习题：找棋盘图、认棋子、读"黑先"和题号。
        .target(name: "GoVision", dependencies: ["GoCore"], swiftSettings: optimizedInDebug),
        // 棋盘和摆题界面，iOS 和 macOS 都能编译。
        .target(name: "GoUI", dependencies: ["GoCore", "GoVision"]),
        // 开发工具：把棋盘渲染成 PNG，没有模拟器时也能检查画面。
        .executableTarget(
            name: "board-snapshot",
            dependencies: ["GoCore", "GoUI"],
            path: "Tools/BoardSnapshot"
        ),
        .testTarget(name: "GoCoreTests", dependencies: ["GoCore"]),
        .testTarget(name: "GoVisionTests", dependencies: ["GoVision"]),
        .testTarget(name: "GoUITests", dependencies: ["GoUI", "GoVision"]),
    ]
)
