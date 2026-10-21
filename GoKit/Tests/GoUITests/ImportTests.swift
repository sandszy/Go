import CoreGraphics
import GoCore
import GoVision
import Testing
@testable import GoUI

/// 识别结果进到摆题界面以后的行为。识别本身在 GoVisionTests 里测。
@MainActor
@Suite("照片导入")
struct ImportTests {
    private let photo: CGImage = {
        let context = CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }()

    /// 左下角一道 5×5 的题：黑子在 (1, 3)，白子在 (2, 3)，(3, 3) 没认准。
    private func diagram(id: Int, number: Int) -> RecognizedDiagram {
        var stones = [[Stone?]](repeating: [Stone?](repeating: nil, count: 5), count: 5)
        stones[3][1] = .black
        stones[3][2] = .white
        return RecognizedDiagram(
            id: id,
            number: number,
            bounds: CGRect(x: 20, y: 20, width: 80, height: 80),
            columns: 5,
            rows: 5,
            edges: [.left, .bottom],
            stones: stones,
            uncertain: [GridPoint(column: 3, row: 3)]
        )
    }

    private func page(_ diagrams: [RecognizedDiagram]) -> RecognizedPage {
        RecognizedPage(imageSize: CGSize(width: 200, height: 200), diagrams: diagrams, toPlay: .black, goal: .capturingRace, pageNumber: 35)
    }

    @Test("一页好几道题时先选题，选好后进摆题模式校对")
    func chooseDiagram() {
        let model = ProblemEditorModel()
        model.switchMode(to: .solve)
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8)]), from: photo)
        #expect(model.isChoosingDiagram)

        model.loadDiagram(1)
        #expect(!model.isChoosingDiagram)
        #expect(model.mode == .setup)
        #expect(model.tool == .cycle)
        #expect(model.problem.title == "第 35 页第 8 题")
        #expect(model.problem.goal == .capturingRace)
        // 左下角：第 3 行在 19 路棋盘上是 y = 14 + 3 = 17。
        #expect(model.problem.setup[Point(1, 17)] == .black)
        #expect(model.problem.setup[Point(2, 17)] == .white)
        #expect(model.uncertainPoints == [Point(3, 17)])
        #expect(model.referenceImage != nil)
        #expect(model.region == BoardRegion(minX: 0, minY: 14, maxX: 4, maxY: 18))
    }

    @Test("只有一道题就直接导入")
    func singleDiagram() {
        let model = ProblemEditorModel()
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        #expect(!model.isChoosingDiagram)
        #expect(model.problem.title == "第 35 页第 7 题")
    }

    @Test("没找到棋盘图时提示换个角度")
    func noDiagram() {
        let model = ProblemEditorModel()
        model.show(page([]), from: photo)
        #expect(model.message?.tone == .warning)
        #expect(model.scannedPage == nil)
    }

    @Test("轮换工具：空、黑、白、空，改过的点不再提醒")
    func cycleTool() {
        let model = ProblemEditorModel()
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        let p = Point(3, 17)
        model.tap(p)
        #expect(model.problem.setup[p] == .black)
        #expect(!model.uncertainPoints.contains(p))
        model.tap(p)
        #expect(model.problem.setup[p] == .white)
        model.tap(p)
        #expect(model.problem.setup[p] == nil)
    }

    @Test("显示全盘时不按印的范围；换棋盘大小时清掉原图")
    func wholeBoardAndReset() {
        let model = ProblemEditorModel()
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        model.showWholeBoard = true
        #expect(model.region == .full(size: 19))
        model.showWholeBoard = false
        model.switchMode(to: .solve)
        #expect(model.region == BoardRegion(minX: 0, minY: 14, maxX: 4, maxY: 18))

        model.switchMode(to: .setup)
        model.changeBoardSize(to: 9)
        #expect(model.problem.region == nil)
        #expect(model.referenceImage == nil)
        #expect(model.uncertainPoints.isEmpty)
    }
}
