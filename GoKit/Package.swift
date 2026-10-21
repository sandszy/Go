// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GoCore", targets: ["GoCore"]),
        .library(name: "GoUI", targets: ["GoUI"]),
    ],
    targets: [
        // 规则引擎、题目模型和判题，纯 Swift，不依赖界面。
        // 判题要搜索上万个局面，不开优化时慢上百倍，所以调试时也开优化。
        .target(
            name: "GoCore",
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        // 棋盘和摆题界面，iOS 和 macOS 都能编译。
        .target(name: "GoUI", dependencies: ["GoCore"]),
        // 开发工具：把棋盘渲染成 PNG，没有模拟器时也能检查画面。
        .executableTarget(
            name: "board-snapshot",
            dependencies: ["GoCore", "GoUI"],
            path: "Tools/BoardSnapshot"
        ),
        .testTarget(name: "GoCoreTests", dependencies: ["GoCore"]),
        .testTarget(name: "GoUITests", dependencies: ["GoUI"]),
    ]
)
