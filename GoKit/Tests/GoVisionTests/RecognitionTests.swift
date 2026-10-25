import CoreGraphics
import CoreText
import Foundation
import GoCore
import Testing
@testable import GoVision

/// 画一张像练习册那样的棋盘图：白底黑线，棋盘边用粗线，没到边的一侧线条伸出去一点。
/// rows 是字符画，X 黑、O 白、. 空，第一行是图的最上面。给了 caption 时在图上面写一行字，像练习册的题目说明。
/// notes 是页面上别的字（题号、页码），at 是字的左下角，原点在左上角。
private func drawDiagram(
    _ rows: [String],
    edges: DiagramEdges,
    spacing: CGFloat = 40,
    origin: CGPoint = CGPoint(x: 300, y: 250),
    rotation: CGFloat = 0,
    canvas: CGSize = CGSize(width: 1600, height: 1200),
    caption: String? = nil,
    notes: [(text: String, at: CGPoint)] = [],
    verticalGray: CGFloat = 0.1,
    verticalWidth: CGFloat = 1.6,
    extras: (CGContext) -> Void = { _ in }
) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(origin: .zero, size: canvas))
    // 在翻转坐标以前写字，不然字是倒的。CGContext 原点在左下角。
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 48, nil)
    let texts = (caption.map { [(text: $0, at: CGPoint(x: 200, y: 150))] } ?? []) + notes
    for note in texts {
        let text = NSAttributedString(string: note.text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
        ])
        context.textPosition = CGPoint(x: note.at.x, y: canvas.height - note.at.y)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
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
        // 拍的时候手左右晃，竖线糊成浅灰色的宽带；棋盘边的粗线还是黑的。
        context.setStrokeColor(CGColor(gray: isEdge ? 0.1 : verticalGray, alpha: 1))
        context.setLineWidth(isEdge ? 5 : verticalWidth)
        context.move(to: CGPoint(x: x, y: edges.contains(.top) ? 0 : -overhang))
        context.addLine(to: CGPoint(x: x, y: edges.contains(.bottom) ? depth : depth + overhang))
        context.strokePath()
    }
    context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
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
    extras(context)
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

/// 每个测试都要用系统的文字识别，好几个同时跑时 swift test 会卡住不动，所以一个一个跑。
@Suite("习题识别", .serialized)
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

    @Test("照片转了方向：按页面上的字转正，左下角的题还贴在左下角", arguments: [1, 2, 3])
    func uprightsTurnedPage(_ turns: Int) throws {
        let page = drawDiagram(sampleDiagram, edges: [.left, .bottom], caption: "黑先，请找出对杀取胜的一手。")
        let turned = try #require(PageOrientation.redraw(page, maxDimension: 1600, quarterTurns: turns))
        #expect(PageOrientation.quarterTurns(of: turned) == (4 - turns) % 4)
        let recognized = try PageRecognizer.recognize(PageOrientation.upright(turned))
        let found = try #require(recognized.diagrams.first)
        #expect(found.edges == [.left, .bottom])
        #expect(diagram(found) == sampleDiagram)
        #expect(recognized.toPlay == .black)
    }

    @Test("页面上没有字时看不出方向，照片不转")
    func keepsPageWithoutText() throws {
        let page = drawDiagram(sampleDiagram, edges: [.left, .bottom])
        let turned = try #require(PageOrientation.redraw(page, maxDimension: 1600, quarterTurns: 2))
        #expect(PageOrientation.quarterTurns(of: turned) == 0)
        #expect(PageOrientation.quarterTurns(of: drawDiagram(sampleDiagram, edges: [.left, .bottom], caption: "黑先，请找出对杀取胜的一手。")) == 0)
    }

    @Test("照片晃糊了，竖线成了浅灰色的宽带，也能认，空点不标没认准")
    func blurredLines() throws {
        // 浅到按局部阈值不算墨（第 34 页那张就是这样）。
        let image = drawDiagram(sampleDiagram, edges: [.left, .bottom], verticalGray: 0.75, verticalWidth: 6)
        let found = try #require(try PageRecognizer.recognize(image).diagrams.first)
        #expect(diagram(found) == sampleDiagram)
        #expect(found.uncertain.isEmpty)
    }

    @Test("铅笔印、橡皮屑不当黑子，标成没认准：小的不够圆，大的颜色比印的黑子浅得多")
    func pencilMarks() throws {
        // 画在两个空点上：第 2 行第 4 列一个小的，第 3 行第 7 列一个和棋子差不多大、浅灰的。
        // 坐标以图的左上角为原点，一格 40 像素。
        let image = drawDiagram(sampleDiagram, edges: [.left, .bottom]) { context in
            context.setFillColor(CGColor(gray: 0.45, alpha: 1))
            context.fillEllipse(in: CGRect(x: 3 * 40 - 9, y: 1 * 40 - 8, width: 18, height: 16))
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fillEllipse(in: CGRect(x: 6 * 40 - 17, y: 2 * 40 - 17, width: 34, height: 34))
        }
        let found = try #require(try PageRecognizer.recognize(image).diagrams.first)
        #expect(diagram(found) == sampleDiagram)
        #expect(found.uncertain.isSuperset(of: [GridPoint(column: 3, row: 1), GridPoint(column: 6, row: 2)]))
    }

    @Test("右边挨着一条从上到下的书缝阴影：不当成一列，也不当成黑子")
    func gutterShadow() throws {
        // 横线伸到最后一列外 0.4 格；再往右 0.2 格，一条 0.25 格宽、从照片顶上通到底下的暗带。
        let image = drawDiagram(sampleDiagram, edges: [.left, .bottom]) { context in
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(CGRect(x: 8.6 * 40, y: -250, width: 10, height: 1200))
        }
        let found = try #require(try PageRecognizer.recognize(image).diagrams.first)
        #expect(found.columns == 9)
        #expect(diagram(found) == sampleDiagram)
    }

    @Test("书页卷得厉害，最后一列整个压在又黑又宽的阴影里：不当成一列黑子，留空、标成没认准")
    func curledColumn() throws {
        // 最后一列正好在一条 0.6 格宽、从照片顶上通到底下的暗带中间。
        let image = drawDiagram(sampleDiagram, edges: [.left, .bottom]) { context in
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 8 * 40 - 12, y: -250, width: 24, height: 1200))
        }
        let found = try #require(try PageRecognizer.recognize(image).diagrams.first)
        #expect(found.stones.allSatisfy { $0.last! == nil })
        #expect(diagram(found).map { String($0.prefix(8)) } == sampleDiagram.map { String($0.prefix(8)) })
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
        let problem = found.problem(title: "", toPlay: .black, goal: .capturingRace)
        #expect(problem.setup[Point(16, 1)] == .black)
        #expect(problem.setup[Point(17, 1)] == .white)
        #expect(problem.setup[Point(17, 2)] == .white)
    }

    /// 第 43 页那张照片底下没拍到页码，最下面一行的题号“23”刚好落进下面四分之一，灰底的圆圈又没找到，在 iPad 上读成了页码。
    @Test("最下面一行的题号落进照片下面四分之一，旁边没找到圆圈，也不当页码；底下真有页码照样读出来")
    func problemNumberIsNotPageNumber() throws {
        let rows = [
            ".....X...",
            "..XXXOO..",
            ".XOOOXO..",
            ".....XO..",
            ".........",
        ]
        let number = (text: "23", at: CGPoint(x: 200, y: 960))
        let page = try PageRecognizer.recognize(drawDiagram(rows, edges: [.left, .bottom], origin: CGPoint(x: 300, y: 920), notes: [number]))
        #expect(page.diagrams.map(\.number) == [23])
        #expect(page.pageNumber == nil)

        let withPageNumber = try PageRecognizer.recognize(drawDiagram(
            rows, edges: [.left, .bottom], origin: CGPoint(x: 300, y: 920), notes: [number, (text: "43", at: CGPoint(x: 780, y: 1150))]
        ))
        #expect(withPageNumber.pageNumber == 43)
    }

    @Test("从文字里读出黑先、题型和题号")
    func readsText() {
        let items = [
            TextItem(text: "4-2.对杀", box: .zero),
            TextItem(text: "黑先，请找出对杀取胜的一手。", box: .zero),
        ]
        #expect(TextReader.toPlay(in: items) == .black)
        #expect(TextReader.goal(in: items) == .capturingRace)
        // 七种题型按外框的摆法归成三种。
        func goal(_ text: String) -> ProblemGoal? { TextReader.goal(in: [TextItem(text: text, box: .zero)]) }
        #expect(goal("黑先做活") == .capture)
        #expect(goal("黑先杀白") == .escape)
        #expect(goal("切断") == .capturingRace)
        #expect(goal("黑先") == nil)
        #expect(TextReader.number(in: "⑦") == 7)
        #expect(TextReader.number(in: " 12 ") == 12)
        #expect(TextReader.number(in: "4-2") == nil)
    }
}

/// 样例照片不进仓库（是孩子的作业），本机有的时候才测。放在仓库根目录的“棋盘照片样例”或 Samples 文件夹里。
private let sampleFolder: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let samplePhotos: [URL] = ["棋盘照片样例", "Samples"].flatMap { name in
    let folder = sampleFolder.appendingPathComponent(name)
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return files.filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
}.sorted { $0.lastPathComponent < $1.lastPathComponent }

/// 读照片的测试排着一个一个跑：好几个同时用系统的文字识别时，swift test 会卡住不动。
@Suite("照片", .serialized)
struct PhotoSuites {}

/// 第 35 页那张，下面的测试按它的内容写了具体的期望。
private let samplePhoto: URL? = samplePhotos.first { $0.lastPathComponent == "棋盘照片样例.HEIC" }

extension PhotoSuites {
@Suite("样例照片", .enabled(if: samplePhoto != nil, "本机没有样例照片"))
struct SamplePhotoTests {
    @Test("第 35 页：6 道对杀题，黑先，第 7 题和手抄的一样")
    func samplePage() throws {
        let image = try #require(PhotoLoader.image(at: samplePhoto!))
        let page = try PageRecognizer.recognize(image)
        for found in page.diagrams {
            print("第 \(found.number.map(String.init) ?? "?") 题\(found.isIncomplete ? "（没拍全）" : "") \(found.columns)×\(found.rows) 边 \(found.edges.rawValue) 不确定 \(found.uncertain.count) 数字 \(found.labels.map { "(\($0.key.column),\($0.key.row))=\($0.value)" })")
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
}

/// 把每张样例照片的识别结果打印出来，人工对照照片检查。新照片放进去就会跑。
extension PhotoSuites {
@Suite("所有样例照片", .enabled(if: !samplePhotos.isEmpty, "本机没有样例照片"))
struct AllSamplePhotosTests {
    @Test("识别每张照片", arguments: samplePhotos)
    func survey(_ url: URL) throws {
        let image = try #require(PhotoLoader.image(at: url))
        // 和 App 导入时一样，先按文字方向转正。
        let page = try PageRecognizer.recognize(PageOrientation.upright(image))
        print("===== \(url.lastPathComponent)：第 \(page.pageNumber.map(String.init) ?? "?") 页 \(page.toPlay?.name ?? "?")先 题型 \(page.goal?.name ?? "?") 共 \(page.diagrams.count) 图 没认出 \(page.missingNumbers)")
        for found in page.diagrams {
            print("第 \(found.number.map(String.init) ?? "?") 题\(found.isIncomplete ? "（没拍全）" : "") \(found.columns)×\(found.rows) 边 \(found.edges.rawValue) 不确定 \(found.uncertain.count) 数字 \(found.labels.map { "(\($0.key.column),\($0.key.row))=\($0.value)" }) 位置 \(Int(found.bounds.minX)),\(Int(found.bounds.minY)) \(Int(found.bounds.width))×\(Int(found.bounds.height))")
            print(diagram(found).joined(separator: "\n"))
        }
    }
}
}

private func photo(_ name: String) -> URL? { samplePhotos.first { $0.lastPathComponent == name } }

/// 2026-10 拍的几页练习册：拍歪、阴影、书页弯曲、反光、棋子摆得很密。
extension PhotoSuites {
@Suite("新样例照片", .enabled(if: photo("IMG_0325.HEIC") != nil, "本机没有这几张样例照片"))
struct MoreSamplePhotosTests {
    private func page(_ name: String) throws -> RecognizedPage {
        let url = try #require(photo(name))
        let image = try #require(PhotoLoader.image(at: url))
        return try PageRecognizer.recognize(image)
    }

    @Test("第 37 页：拍歪了、棋子很密，6 道题都认出来；23 题只读出 \"3\" 时按前后题号改正")
    func page37() throws {
        let page = try page("IMG_0325.HEIC")
        #expect(page.pageNumber == 37)
        #expect(page.goal == .capturingRace)
        #expect(page.diagrams.map(\.number) == [19, 20, 21, 22, 23, 24])
        #expect(page.diagrams.allSatisfy { $0.columns == 9 && $0.rows == 9 && !$0.isIncomplete })
        // 夹在黑子中间的白子：23 题第 8 行第 6 列，24 题第 7 行第 2、3 列。
        #expect(diagram(page.diagrams[4])[7] == ".OX.XOXXO")
        #expect(diagram(page.diagrams[5])[6] == "XOOXOXOX.")
    }

    @Test("第 36 页：16、18 题反光，只认出左边几列，和 14 题一样标成没拍全，补成 9 列")
    func page36() throws {
        let page = try page("IMG_0326.HEIC")
        #expect(page.pageNumber == 36)
        #expect(page.diagrams.map(\.number) == [13, 14, 15, 16, 17, 18])
        #expect(page.diagrams.map(\.isIncomplete) == [false, true, false, true, false, true])
        #expect(page.missingNumbers == [])
        #expect(page.diagrams.allSatisfy { $0.columns == 9 && $0.rows == 9 })
        // 16 题认出来的左边 4 列，右边补的是空的。
        #expect(diagram(page.diagrams[3])[3] == "..XX.....")
        // 17 题拍得最歪（横线斜率约 0.1）。
        #expect(diagram(page.diagrams[4])[6] == ".OXXOOX.X")
    }

    @Test("第 36 页另一张：14 题挨着书缝也认出来，16 题书缝的阴影不当白子，18 题横竖线距不一样也对")
    func page36Again() throws {
        let page = try page("IMG_0352.HEIC")
        #expect(page.pageNumber == 36)
        #expect(page.diagrams.map(\.number) == [13, 14, 15, 16, 17, 18])
        #expect(page.diagrams.map(\.isIncomplete) == [false, true, false, false, false, false])
        #expect(diagram(page.diagrams[3])[0] == ".........")
        let eighteen = page.diagrams[5]
        #expect(eighteen.columns == 9 && eighteen.rows == 9 && eighteen.edges == [.left, .bottom])
        #expect(diagram(eighteen)[7] == "OXXOO.O..")
    }

    @Test("倒过来拍的照片转正以后，认出来的和正着拍的一样")
    func turnedPhoto() throws {
        let url = try #require(photo("IMG_0352.HEIC"))
        let image = try #require(PhotoLoader.image(at: url))
        let turned = try #require(PageOrientation.redraw(image, maxDimension: max(image.width, image.height), quarterTurns: 2))
        let page = try PageRecognizer.recognize(PageOrientation.upright(turned))
        #expect(page.pageNumber == 36)
        #expect(page.diagrams.map(\.number) == [13, 14, 15, 16, 17, 18])
        #expect(page.diagrams.allSatisfy { $0.edges == [.left, .bottom] })
    }

    @Test("扑：吃子题，照片下面露出半截的 11、12 题不要，题号圈和白子上的数字不当页码")
    func pounce() throws {
        let page = try page("IMG_0329.HEIC")
        #expect(page.goal == .capture)
        #expect(page.toPlay == .black)
        #expect(page.diagrams.map(\.number) == [7, 8, 9, 10])
        #expect(page.pageNumber == nil)
    }

    @Test("章节扉页上的装饰棋盘不当成题")
    func titlePage() throws {
        #expect(try page("IMG_0328.HEIC").diagrams.isEmpty)
    }
}
}

@Suite("题号")
struct NumberingTests {
    @Test("题号中间断开的就是没认出来的题")
    func missingNumbers() {
        func diagram(_ number: Int?) -> RecognizedDiagram {
            RecognizedDiagram(id: number ?? 0, number: number, bounds: .zero, columns: 9, rows: 9, edges: [], stones: [])
        }
        #expect(RecognizedPage(imageSize: .zero, diagrams: [13, 14, 15, 17].map(diagram)).missingNumbers == [16])
        #expect(RecognizedPage(imageSize: .zero, diagrams: [7, 8].map(diagram)).missingNumbers == [])
        #expect(RecognizedPage(imageSize: .zero, diagrams: [diagram(nil)]).missingNumbers == [])
    }
}

@Suite("题号补全")
struct NumberSequenceTests {
    /// 两列三行，按阅读顺序读出的题号。
    private func page(_ numbers: [Int?]) -> [Int?] {
        var diagrams = numbers.enumerated().map { index, number in
            RecognizedDiagram(
                id: index, number: number, bounds: CGRect(x: 400 + 700 * (index % 2), y: 400 + 600 * (index / 2), width: 500, height: 500),
                columns: 9, rows: 9, edges: [], stones: []
            )
        }
        PageRecognizer.fillNumberSequence(&diagrams)
        return diagrams.map(\.number)
    }

    @Test("带圈的两位数只读出一位：10 读成 \"0\"、19 读成 \"1\"，按别的题号和版面改正")
    func partialNumbers() {
        #expect(page([nil, nil, nil, 0, 11, 12]) == [7, 8, 9, 10, 11, 12])
        #expect(page([1, 20, 2, 2, 23, 24]) == [19, 20, 21, 22, 23, 24])
        #expect(page([13, 14, 5, 6, 7, 18]) == [13, 14, 15, 16, 17, 18])
    }

    @Test("两道一字不差、超过一半对得上，就按它们改正读错的；对不上的太多就不动")
    func twoExactNumbers() {
        #expect(page([nil, 2, nil, nil, 5, 9]) == [1, 2, 3, 4, 5, 6])
        #expect(page([7, 30, 41, nil, nil, nil]) == [7, 30, 41, nil, nil, nil])
    }
}

@Suite("书缝阴影")
struct ShadowLineTests {
    private func diagram(edges: DiagramEdges, black column: Int) -> RecognizedDiagram {
        var stones = [[Stone?]](repeating: [Stone?](repeating: nil, count: 9), count: 9)
        for row in 1..<9 { stones[row][column] = .black }
        stones[8][4] = .black
        return RecognizedDiagram(id: 0, number: 1, bounds: .zero, columns: 9, rows: 9, edges: edges, stones: stones)
    }

    @Test("不是棋盘边的最外面一列大半是黑子：是书缝的阴影，清空，标成没认准；别的子不动")
    func clearsBlackColumn() {
        var diagrams = [diagram(edges: [.left, .bottom], black: 8)]
        PageRecognizer.clearShadowLines(&diagrams)
        #expect(diagrams[0].stones.allSatisfy { $0[8] == nil })
        #expect(diagrams[0].uncertain.count == 8)
        #expect(diagrams[0].stones[8][4] == .black)
    }

    @Test("棋盘边那一列摆满黑子是真的，不动")
    func keepsBoardEdge() {
        var diagrams = [diagram(edges: [.left, .bottom], black: 0)]
        PageRecognizer.clearShadowLines(&diagrams)
        #expect(diagrams[0].stones.dropFirst().allSatisfy { $0[0] == .black })
        #expect(diagrams[0].uncertain.isEmpty)
    }
}

@Suite("版面格子")
struct LayoutSlotTests {
    private func diagram(_ number: Int?, x: Double, y: Double) -> RecognizedDiagram {
        RecognizedDiagram(id: Int(x + y), number: number, bounds: CGRect(x: x, y: y, width: 500, height: 500), columns: 9, rows: 9, edges: [], stones: [])
    }

    @Test("两列三行、少了右边中间那个：按格子数，不按认出来的个数")
    func slotsSkipMissingDiagram() {
        let diagrams = [diagram(13, x: 470, y: 400), diagram(14, x: 1260, y: 380), diagram(15, x: 465, y: 1010), diagram(nil, x: 440, y: 1615)]
        #expect(PageRecognizer.layoutSlots(of: diagrams) == [0, 1, 2, 4])
    }
}

@Suite("没拍全")
struct IncompleteTests {
    private func diagram(_ id: Int, columns: Int, edges: DiagramEdges) -> RecognizedDiagram {
        var stones = [[Stone?]](repeating: [Stone?](repeating: nil, count: columns), count: 9)
        stones[8][0] = .black
        return RecognizedDiagram(id: id, number: id, bounds: .zero, columns: columns, rows: 9, edges: edges, stones: stones, uncertain: [GridPoint(column: 0, row: 8)])
    }

    @Test("比同一页别的图少几列：从棋盘边那一侧量，补成一样大，补的是空点")
    func padsToPageSize() {
        var diagrams = (1...3).map { diagram($0, columns: 9, edges: [.left, .bottom]) } + [diagram(4, columns: 5, edges: [.left, .bottom]), diagram(5, columns: 8, edges: [.right, .bottom])]
        PageRecognizer.markIncomplete(&diagrams)
        #expect(diagrams.map(\.isIncomplete) == [false, false, false, true, true])
        #expect(diagrams.allSatisfy { $0.columns == 9 && $0.stones.allSatisfy { $0.count == 9 } })
        #expect(diagrams[3].stones[8] == [.black] + [Stone?](repeating: nil, count: 8), "左边是棋盘边，补在右边")
        #expect(diagrams[4].stones[8][1] == .black, "右边是棋盘边，补在左边，原来的子往右挪")
        #expect(diagrams[4].uncertain == [GridPoint(column: 1, row: 8)])
    }

    @Test("左右都不是棋盘边时不知道缺哪边，不补，只标没拍全")
    func noPaddingWithoutEdge() {
        var diagrams = (1...3).map { diagram($0, columns: 9, edges: [.left, .bottom]) } + [diagram(4, columns: 6, edges: [.bottom])]
        PageRecognizer.markIncomplete(&diagrams)
        #expect(diagrams[3].isIncomplete)
        #expect(diagrams[3].columns == 6)
    }
}
