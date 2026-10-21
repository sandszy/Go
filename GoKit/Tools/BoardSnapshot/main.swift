// 把棋盘渲染成 PNG，没有模拟器时也能检查画面。
// 用法：swift run board-snapshot <输出目录>
import Foundation
import GoCore
import GoUI
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum SnapshotError: Error {
    case renderFailed(String)
    case writeFailed(String)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

@MainActor
func save(_ view: some View, width: CGFloat, height: CGFloat, name: String) throws {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = 2
    guard let image = renderer.cgImage else { throw SnapshotError.renderFailed(name) }
    let url = outputDirectory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw SnapshotError.writeFailed(url.path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw SnapshotError.writeFailed(url.path) }
    print("已保存 \(url.path)")
}

let sample = Problem.sample

// 摆题：全盘，带坐标。
try save(
    BoardView(board: sample.setup, labels: sample.labels, showCoordinates: true),
    width: 700, height: 700, name: "setup-full-board.png"
)

// 做题：只显示左下角，黑棋准备下在下数第 1 行的虚影。
try save(
    BoardView(
        board: sample.setup,
        region: .fitting(sample.setup),
        labels: sample.labels,
        ghost: GhostStone(point: Point(4, 17), stone: .black)
    ),
    width: 700, height: 560, name: "solve-region.png"
)

// 9 路：最后一手标记、星位，以及摆错时没有气的子用红圈标出。
let nine = Board(diagram: """
    . . . . . . . . .
    . . . . . . . . .
    . . X O . . . . .
    . X O . O . . . .
    . . X O . . . . .
    . . . . . . X . .
    . . . . . . . . .
    X . . . . . . . .
    O X . . . . . . .
    """)
try save(
    BoardView(
        board: nine,
        lastMove: Point(6, 5),
        highlighted: Set(nine.groupsWithoutLiberties.flatMap { $0 }),
        showCoordinates: true
    ),
    width: 600, height: 600, name: "nine-by-nine.png"
)
