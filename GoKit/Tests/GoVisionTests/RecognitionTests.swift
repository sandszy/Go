import CoreGraphics
import Foundation
import GoCore
import Testing
@testable import GoVision

/// 画一张像练习册那样的棋盘图：白底黑线，棋盘边用粗线，没到边的一侧线条伸出去一点。
/// rows 是字符画，X 黑、O 白、. 空，第一行是图的最上面。
private func drawDiagram(
    _ rows: [String],
    edges: DiagramEdges,
    spacing: CGFloat = 40,
    origin: CGPoint = CGPoint(x: 300, y: 250),
    rotation: CGFloat = 0,
    canvas: CGSize = CGSize(width: 1600, height: 1200)
) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(origin: .zero, size: canvas))
    // 换成左上角原点，和照片一样。
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: origin.x, y: origin.y)
    context.rotate(by: rotation)

    let columns = rows[0].count, height = rows.count
    let width = CGFloat(columns - 1) * spacing, depth = CGFloat(height - 1) * spacing
    let overhang = spacing * 0.4
    context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
    for column in 0..<columns {
        let x = CGFloat(column) * spacing
        let isEdge = (column == 0 && edges.contains(.left)) || (column == columns - 1 && edges.contains(.right))
        context.setLineWidth(isEdge ? 5 : 1.6)
        context.move(to: CGPoint(x: x, y: edges.contains(.top) ? 0 : -overhang))
        context.addLine(to: CGPoint(x: x, y: edges.contains(.bottom) ? depth : depth + overhang))
        context.strokePath()
    }
    for row in 0..<height {
        let y = CGFloat(row) * spacing
        let isEdge = (row == 0 && edges.contains(.top)) || (row == height - 1 && edges.contains(.bottom))
        context.setLineWidth(isEdge ? 5 : 1.6)
        context.move(to: CGPoint(x: edges.contains(.left) ? 0 : -overhang, y: y))
        context.addLine(to: CGPoint(x: edges.contains(.right) ? width : width + overhang, y: y))
        context.strokePath()
    }
    let radius = spacing * 0.46
    for (row, line) in rows.enumerated() {
        for (column, char) in line.enumerated() where char != "." {
            let rect = CGRect(x: CGFloat(column) * spacing - radius, y: CGFloat(row) * spacing - radius, width: radius * 2, height: radius * 2)
            if char == "X" {
                context.setFillColor(CGColor(gray: 0.08, alpha: 1))
                context.fillEllipse(in: rect)
            } else {
                context.setFillColor(CGColor(gray: 0.98, alpha: 1))
                context.fillEllipse(in: rect)
                context.setLineWidth(1.6)
                context.strokeEllipse(in: rect)
            }
        }
    }
    return context.makeImage()!
}

private func diagram(_ recognized: RecognizedDiagram) -> [String] {
    recognized.stones.map { row in
        String(row.map { $0 == .black ? "X" : $0 == .white ? "O" : "." })
    }
}

/// 第 7 题的样子：左下角，9 列 9 行。
private let sampleDiagram = [
    ".........",
    ".........",
    ".........",
    ".........",
    ".....X...",
    "..XXXOO..",
    ".XOOOXO..",
    ".....XO..",
    ".........",
]

@Suite("习题识别")
struct RecognitionTests {
    @Test("认出画好的棋盘图：大小、棋盘边和每颗子")
    func drawnDiagram() throws {
        let page = try PageRecognizer.recognize(drawDiagram(sampleDiagram, edges: [.left, .bottom]))
        let found = try #require(page.diagrams.first)
        #expect(page.diagrams.count == 1)
        #expect(found.columns == 9)
        #expect(found.rows == 9)
        #expect(found.edges == [.left, .bottom])
        #expect(diagram(found) == sampleDiagram)
        #expect(found.uncertain.isEmpty, "\(found.uncertain)")
    }

    @Test("照片拍歪一点也能认")
    func rotatedDiagram() throws {
        let image = drawDiagram(sampleDiagram, edges: [.left, .bottom], rotation: 1.5 * .pi / 180)
        let found = try #require(try PageRecognizer.recognize(image).diagrams.first)
        #expect(diagram(found) == sampleDiagram)
        #expect(found.edges == [.left, .bottom])
    }

    @Test("放到 19 路棋盘的左下角，显示区域和印的一样")
    func placesDiagramOnBoard() throws {
        let found = try #require(try PageRecognizer.recognize(drawDiagram(sampleDiagram, edges: [.left, .bottom])).diagrams.first)
        let problem = found.problem(title: "", toPlay: .black, goal: .capturingRace)
        #expect(problem.setup == Problem.sample.setup)
        #expect(problem.region == BoardRegion(minX: 0, minY: 10, maxX: 8, maxY: 18))
    }

    @Test("右上角的题贴到右上角")
    func topRightCorner() throws {
        let rows = [
            "......",
            "...XO.",
            "....O.",
            "......",
            "......",
        ]
        let found = try #require(try PageRecognizer.recognize(drawDiagram(rows, edges: [.top, .right])).diagrams.first)
        #expect(found.edges == [.top, .right])
        let problem = found.problem(title: "", toPlay: .black, goal: nil)
        #expect(problem.setup[Point(16, 1)] == .black)
        #expect(problem.setup[Point(17, 1)] == .white)
        #expect(problem.setup[Point(17, 2)] == .white)
    }

    @Test("从文字里读出黑先、题型和题号")
    func readsText() {
        let items = [
            TextItem(text: "4-2.对杀", box: .zero),
            TextItem(text: "黑先，请找出对杀取胜的一手。", box: .zero),
        ]
        #expect(TextReader.toPlay(in: items) == .black)
        #expect(TextReader.goal(in: items) == .capturingRace)
        #expect(TextReader.number(in: "⑦") == 7)
        #expect(TextReader.number(in: " 12 ") == 12)
        #expect(TextReader.number(in: "4-2") == nil)
    }
}

/// 样例照片不进仓库（是孩子的作业），本机有的时候才测。
private let samplePhoto: URL? = {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [root.appendingPathComponent("棋盘照片样例.HEIC")]
        + ((try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Samples"), includingPropertiesForKeys: nil)) ?? [])
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}()

@Suite("样例照片", .enabled(if: samplePhoto != nil, "本机没有样例照片"))
struct SamplePhotoTests {
    @Test("第 35 页：6 道对杀题，黑先，第 7 题和手抄的一样")
    func samplePage() throws {
        let image = try #require(PhotoLoader.image(at: samplePhoto!))
        let page = try PageRecognizer.recognize(image)
        for found in page.diagrams {
            print("第 \(found.number.map(String.init) ?? "?") 题 \(found.columns)×\(found.rows) 边 \(found.edges.rawValue) 不确定 \(found.uncertain.count) 数字 \(found.labels.map { "(\($0.key.column),\($0.key.row))=\($0.value)" })")
            print(diagram(found).joined(separator: "\n"))
        }

        #expect(page.diagrams.count == 6)
        #expect(page.diagrams.allSatisfy { $0.columns == 9 && $0.rows == 9 && $0.edges == [.left, .bottom] })
        #expect(page.toPlay == .black)
        #expect(page.goal == .capturingRace)

        #expect(page.diagrams.map(\.number) == [7, 8, 9, 10, 11, 12])
        #expect(page.pageNumber == 35)

        let seven = try #require(page.diagrams.first)
        let problem = page.problem(for: seven)
        #expect(problem.title == "第 35 页第 7 题")
        #expect(problem.setup == Problem.sample.setup)
        #expect(problem.labels[Point(6, 17)] == "1")
    }
}
