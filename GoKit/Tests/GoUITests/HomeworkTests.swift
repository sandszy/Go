import CoreGraphics
import Foundation
import GoCore
import GoVision
import Testing
@testable import GoUI

/// 作业本：拍的题自动存、手摆的题按按钮存、以后选一道加载。每个测试用自己的临时目录。
@MainActor
@Suite("作业本")
struct HomeworkTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "作业本测试-\(UUID().uuidString)")

    private let photo: CGImage = {
        let context = CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }()

    /// 左下角一道 5×5 的题：黑子在 (1, 3)，白子在 (2, 3)。
    private func diagram(id: Int, number: Int, incomplete: Bool = false) -> RecognizedDiagram {
        var stones = [[Stone?]](repeating: [Stone?](repeating: nil, count: 5), count: 5)
        stones[3][1] = .black
        stones[3][2] = .white
        var diagram = RecognizedDiagram(
            id: id, number: number, bounds: CGRect(x: 20, y: 20, width: 80, height: 80),
            columns: 5, rows: 5, edges: [.left, .bottom], stones: stones
        )
        diagram.isIncomplete = incomplete
        return diagram
    }

    private func page(_ diagrams: [RecognizedDiagram]) -> RecognizedPage {
        RecognizedPage(imageSize: CGSize(width: 200, height: 200), diagrams: diagrams, toPlay: .black, goal: .capturingRace, pageNumber: 35)
    }

    private func files(_ ext: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == ext }
    }

    @Test("存、重新打开读回来、覆盖、删除")
    func storeRoundTrip() {
        let store = HomeworkStore(directory: directory)
        var saved = SavedProblem(problem: .sample, hasPhoto: true)
        store.save(saved, photo: photo)
        #expect(store.contains(saved.id))

        let reopened = HomeworkStore(directory: directory)
        #expect(reopened.problems == [saved])
        #expect(reopened.photo(for: saved.id)?.width == 200)

        saved.problem.title = "改了名字"
        reopened.save(saved)
        #expect(reopened.problems.count == 1)
        #expect(HomeworkStore(directory: directory).problems.first?.problem.title == "改了名字")
        #expect(reopened.photo(for: saved.id) != nil, "只改题目时原图还在")

        reopened.delete(saved.id)
        #expect(reopened.problems.isEmpty)
        #expect(files("json").isEmpty)
        #expect(files("jpg").isEmpty)
    }

    @Test("例题只放一次，删了不再放回来")
    func exampleOnce() {
        let store = HomeworkStore(directory: directory)
        store.addExampleOnce()
        store.addExampleOnce()
        #expect(store.problems.map(\.problem.title) == ["例题：第 35 页第 7 题"])
        #expect(store.problems.first?.problem.setup == Problem.sample.setup)

        store.delete(store.problems[0].id)
        let reopened = HomeworkStore(directory: directory)
        reopened.addExampleOnce()
        #expect(reopened.problems.isEmpty)
    }

    @Test("以前存的题照常读：七种题型读成三种，没写题型的是对杀")
    func readsOldGoals() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(SavedProblem(problem: .sample))
        let json = try #require(String(data: encoded, encoding: .utf8))
        let expected: [String?: ProblemGoal] = ["live": .capture, "kill": .escape, "connect": .capturingRace, "capture": .capture, nil: .capturingRace]
        for (old, _) in expected {
            let id = UUID()
            var text = json.replacingOccurrences(of: Problem.sample.id.uuidString, with: id.uuidString)
            text = text.replacingOccurrences(of: #""goal":"capturingRace""#, with: old.map { #""goal":"\#($0)""# } ?? #""goal":null"#)
            try Data(text.utf8).write(to: directory.appending(path: "\(id.uuidString).json"))
        }
        let goals = HomeworkStore(directory: directory).problems.map(\.problem.goal)
        #expect(goals.count == expected.count)
        #expect(goals.sorted { $0.rawValue < $1.rawValue } == expected.values.sorted { $0.rawValue < $1.rawValue })
    }

    @Test("读不了的文件跳过")
    func skipsBrokenFiles() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("不是 JSON".utf8).write(to: directory.appending(path: "\(UUID().uuidString).json"))
        let store = HomeworkStore(directory: directory)
        store.save(SavedProblem(problem: .sample))
        #expect(HomeworkStore(directory: directory).problems.count == 1)
    }

    @Test("新存的在前，同一页的按题号排")
    func ordering() {
        let store = HomeworkStore(directory: directory)
        let day = Date(timeIntervalSince1970: 1_000_000)
        for number in [10, 9, 2] {
            store.save(SavedProblem(problem: Problem(title: "第 35 页第 \(number) 题"), saved: day))
        }
        store.save(SavedProblem(problem: Problem(title: "后来摆的"), saved: day.addingTimeInterval(60)))
        #expect(store.problems.map(\.problem.title) == ["后来摆的", "第 35 页第 2 题", "第 35 页第 9 题", "第 35 页第 10 题"])
    }

    @Test("拍的一页里每道题都存进作业本，点进去的就是存的那道")
    func photoSavesEveryDiagram() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8, incomplete: true)]), from: photo)
        let homework = model.homework!
        #expect(homework.problems.map(\.problem.title) == ["第 35 页第 7 题", "第 35 页第 8 题"])
        #expect(homework.problems.map(\.hasPhoto) == [true, true])
        #expect(homework.problems.map(\.isIncomplete) == [false, true])
        #expect(files("jpg").count == 2)

        model.loadDiagram(1)
        #expect(model.saveState == .saved)
        #expect(model.problem.id == homework.problems[1].id)
    }

    @Test("校对改过的题，开始做题时存回作业本")
    func correctionsSavedOnSolve() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        model.tap(Point(3, 17))
        #expect(model.saveState == .modified)

        model.switchMode(to: .solve)
        #expect(model.saveState == .saved)
        #expect(HomeworkStore(directory: directory).problems.first?.problem.setup[Point(3, 17)] == .black)
    }

    @Test("手摆的题点保存才存；清空以后是另一道题")
    func manualSave() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        #expect(model.saveState == .unsaved)
        model.switchMode(to: .solve)
        model.switchMode(to: .setup)
        #expect(model.homework!.problems.isEmpty, "没点保存就不存")

        model.saveProblem()
        #expect(model.saveState == .saved)
        #expect(model.homework!.problems.first?.hasPhoto == false)

        let saved = model.problem
        model.clearBoard()
        #expect(model.saveState == .unsaved)
        model.tap(Point(3, 3))
        model.switchMode(to: .solve)
        #expect(model.homework![saved.id]?.problem == saved, "清空后摆的题不覆盖原来那道")
    }

    @Test("从作业本加载：换一个 App 也能拿出来，有原图对照")
    func load() {
        let first = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        first.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8)]), from: photo)
        first.loadDiagram(1)
        let expected = first.problem

        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.switchMode(to: .solve)
        model.isShowingHomework = true
        let saved = model.homework!.problems.first { $0.id == expected.id }!
        model.load(saved)
        #expect(model.problem == expected)
        #expect(model.mode == .setup)
        #expect(model.referenceImage != nil)
        #expect(model.uncertainPoints.isEmpty)
        #expect(!model.isShowingHomework)
        #expect(model.saveState == .saved)
    }
}
