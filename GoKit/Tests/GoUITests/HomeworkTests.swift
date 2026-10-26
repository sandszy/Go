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

    private func page(_ diagrams: [RecognizedDiagram], number: Int? = 35) -> RecognizedPage {
        RecognizedPage(imageSize: CGSize(width: 200, height: 200), diagrams: diagrams, toPlay: .black, goal: .capturingRace, pageNumber: number)
    }

    private func files(_ ext: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == ext }
    }

    /// 按题目名找作业本里的题。列表里一页是倒着排的，按位置拿容易拿错。
    private func saved(_ title: String, in store: HomeworkStore) -> SavedProblem {
        store.problems.first { $0.problem.title == title }!
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

        // 以前的版本里例题能删：文件没了也不再放回来。
        try? FileManager.default.removeItem(at: directory.appending(path: "\(store.problems[0].id.uuidString).json"))
        let reopened = HomeworkStore(directory: directory)
        reopened.addExampleOnce()
        #expect(reopened.problems.isEmpty)
    }

    @Test("选好几道一起删；全选不选例题，混进来的例题也不删")
    func deleteSeveral() {
        let store = HomeworkStore(directory: directory)
        store.addExampleOnce()
        let problems = (7...9).map { SavedProblem(problem: Problem(title: "第 35 页第 \($0) 题")) }
        for saved in problems { store.save(saved) }
        let example = store.problems.first { $0.isExample }!
        #expect(store.deletableIDs == Set(problems.map(\.id)))

        store.delete([problems[0].id, problems[1].id, example.id])
        #expect(Set(store.problems.map(\.id)) == [problems[2].id, example.id])
        store.delete(store.deletableIDs)
        #expect(store.problems.map(\.id) == [example.id])
        #expect(HomeworkStore(directory: directory).problems.map(\.id) == [example.id])
        #expect(store.deletableIDs.isEmpty)
    }

    @Test("例题删不掉；改过再存还是例题；以前存的例题文件按题目名认出来")
    func exampleKept() throws {
        let store = HomeworkStore(directory: directory)
        store.addExampleOnce()
        var example = try #require(store.problems.first)
        store.delete(example.id)
        #expect(store.problems.count == 1)

        example.problem.title = "改了名字"
        store.save(example)
        #expect(HomeworkStore(directory: directory).problems.first?.isExample == true)

        // 旧版本存的例题：文件里没有 example 这一项。
        let old = SavedProblem(problem: Problem(title: "例题：第 35 页第 7 题"))
        var json = try #require(String(data: JSONEncoder().encode(old), encoding: .utf8))
        json = json.replacingOccurrences(of: #","example":false"#, with: "").replacingOccurrences(of: #""example":false,"#, with: "")
        #expect(!json.contains("example"))
        try Data(json.utf8).write(to: directory.appending(path: "\(old.id.uuidString).json"))
        let reopened = HomeworkStore(directory: directory)
        #expect(reopened[old.id]?.isExample == true)
        reopened.delete(old.id)
        #expect(reopened[old.id] != nil)
        #expect(SavedProblem(problem: Problem(title: "例题：自己摆的")).isExample == false, "新存的题不看题目名")
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

    @Test("列表里新的一天在前；同一天里后存的在前，一次拍照存的按题号倒着排，第一题在最下面")
    func ordering() {
        let store = HomeworkStore(directory: directory)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        for number in [10, 9, 2] {
            store.save(SavedProblem(problem: Problem(title: "第 35 页第 \(number) 题"), saved: day))
        }
        store.save(SavedProblem(problem: Problem(title: "后来摆的"), saved: day.addingTimeInterval(60)))
        store.save(SavedProblem(problem: Problem(title: "早上摆的"), saved: day.addingTimeInterval(-3600)))
        store.save(SavedProblem(problem: Problem(title: "第二天拍的"), saved: day.addingTimeInterval(86_400)))
        #expect(store.problems.map(\.problem.title) == [
            "第二天拍的", "后来摆的", "第 35 页第 10 题", "第 35 页第 9 题", "第 35 页第 2 题", "早上摆的",
        ])
    }

    @Test("拍的一页里每道题都存进作业本，点进去的就是存的那道")
    func photoSavesEveryDiagram() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8, incomplete: true)]), from: photo)
        let homework = model.homework!
        #expect(homework.problems.map(\.problem.title) == ["第 35 页第 8 题", "第 35 页第 7 题"])
        #expect(homework.problems.map(\.hasPhoto) == [true, true])
        #expect(homework.problems.map(\.isIncomplete) == [true, false])
        #expect(files("jpg").count == 2)
        #expect(model.scannedPage?.note == "已存进作业本：第 7、8 题")

        model.loadDiagram(1)
        #expect(model.saveState == .saved)
        #expect(model.problem.id == saved("第 35 页第 8 题", in: homework).id)
    }

    @Test("同一页重拍：同题号的换成新拍的，id 和第一次存的日期不变，不多存一份；以前存的旧文件按题目名认")
    func retakeReplaces() throws {
        // 旧版本存的第 7 题：文件里没有 page、number 两项。
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day = Date(timeIntervalSince1970: 1_000_000)
        let old = SavedProblem(problem: Problem(title: "第 35 页第 7 题"), saved: day, hasPhoto: true)
        let json = try #require(String(data: JSONEncoder().encode(old), encoding: .utf8))
        #expect(!json.contains("\"page\"") && !json.contains("\"number\""), "和旧文件一样，没有页码和题号")
        try Data(json.utf8).write(to: directory.appending(path: "\(old.id.uuidString).json"))

        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        let homework = try #require(model.homework)
        #expect(homework.problems.map(\.id) == [old.id])
        model.show(page([diagram(id: 0, number: 8)]), from: photo)
        #expect(homework.problems.count == 2)

        model.show(page([diagram(id: 0, number: 7, incomplete: true), diagram(id: 1, number: 8), diagram(id: 2, number: 9)]), from: photo)
        #expect(homework.problems.count == 3)
        let seven = try #require(homework[old.id])
        #expect(seven.saved == day)
        #expect(seven.isIncomplete)
        #expect(seven.problem.setup[Point(1, 17)] == .black, "棋子换成了新拍的")
        #expect(seven.page == 35 && seven.number == 7)
        #expect(model.scannedPage?.note == "已存进作业本：第 7～9 题。其中第 7、8 题原来就有，换成了这次拍的")
        #expect(HomeworkStore(directory: directory).problems.count == 3)
    }

    @Test("没读出页码时认不出是不是同一页，照常新存一份")
    func retakeNeedsPageNumber() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8)], number: nil), from: photo)
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8)], number: nil), from: photo)
        #expect(model.homework?.problems.count == 4)
        #expect(model.scannedPage?.note == "已存进作业本：第 7、8 题")
    }

    @Test("存进作业本的提示：三道以上连着的题号写成一段，没读出题号的另外数")
    func importNoteRanges() {
        #expect(ProblemEditorModel.importNote(numbers: [13, 14, 15, 17], unnumbered: 0, replaced: []) == "已存进作业本：第 13～15、17 题")
        #expect(ProblemEditorModel.importNote(numbers: [18, 13, 14, 15, 16, 17], unnumbered: 1, replaced: [13, 14])
            == "已存进作业本：第 13～18 题，还有 1 道没读出题号。其中第 13、14 题原来就有，换成了这次拍的")
        #expect(ProblemEditorModel.importNote(numbers: [], unnumbered: 6, replaced: []) == "已存进作业本：6 道题")
    }

    @Test("只有一道题时直接进摆题，提示开头说存进了作业本；重拍时说原来就有")
    func singleDiagramNote() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        #expect(model.message?.text == "已存进作业本。对照原图检查一下棋子，摆错的地方点一下就能改")
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        #expect(model.message?.text == "作业本里原来就有这道题，换成了这次拍的。对照原图检查一下棋子，摆错的地方点一下就能改")
        #expect(model.homework?.problems.count == 1)
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

    /// 拍一页存进第 7、8（没拍全）、9 题，打开第 7 题开始做。
    private func solvingFirstOfPage() -> ProblemEditorModel {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8, incomplete: true), diagram(id: 2, number: 9)]), from: photo)
        model.load(saved("第 35 页第 7 题", in: model.homework!))
        model.switchMode(to: .solve)
        model.confirmMoves = false
        return model
    }

    @Test("做题时点“下一题”直接做作业本里的下一道；没拍全的照样开始，提示补子")
    func nextProblem() {
        let model = solvingFirstOfPage()
        let eighth = saved("第 35 页第 8 题", in: model.homework!)
        #expect(model.isHomeworkProblem)
        #expect(model.nextHomeworkProblem?.id == eighth.id)
        model.tap(Point(0, 0))
        #expect(model.canUndo)

        model.startNextProblem()
        #expect(model.mode == .solve)
        #expect(model.problem.id == eighth.id)
        #expect(model.position == eighth.problem.startPosition, "从摆好的局面开始，上一道下的子不带过来")
        #expect(!model.canUndo)
        #expect(model.message == EditorMessage(text: "第 35 页第 8 题没拍全，缺的部分先回“摆题”照着书补上", tone: .warning))

        model.startNextProblem()
        #expect(model.problem.id == saved("第 35 页第 9 题", in: model.homework!).id)
        #expect(model.message == EditorMessage(text: "开始做第 35 页第 9 题", tone: .info))
    }

    @Test("“下一题”从早往晚做：前一页做完接着做后拍的那页；列表正好倒过来")
    func nextProblemAcrossPages() {
        let store = HomeworkStore(directory: directory)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        for number in [7, 8] {
            store.save(SavedProblem(problem: Problem(title: "第 35 页第 \(number) 题"), saved: day))
        }
        for number in [13, 14] {
            store.save(SavedProblem(problem: Problem(title: "第 36 页第 \(number) 题"), saved: day.addingTimeInterval(60)))
        }
        #expect(store.problems.map(\.problem.title) == ["第 36 页第 14 题", "第 36 页第 13 题", "第 35 页第 8 题", "第 35 页第 7 题"])

        let model = ProblemEditorModel(homework: store)
        model.load(saved("第 35 页第 8 题", in: store))
        model.switchMode(to: .solve)
        #expect(model.nextHomeworkProblem?.problem.title == "第 36 页第 13 题")
        model.startNextProblem()
        #expect(model.problem.title == "第 36 页第 13 题")
        model.startNextProblem()
        #expect(model.problem.title == "第 36 页第 14 题")
        #expect(model.nextHomeworkProblem == nil, "最后存的那道没有下一题")
    }

    @Test("最后一道没有下一题；手摆的、还没存进作业本的题没有“下一题”")
    func nextProblemAtEnd() {
        let model = solvingFirstOfPage()
        let last = saved("第 35 页第 9 题", in: model.homework!)
        model.startNextProblem()
        model.startNextProblem()
        #expect(model.problem.id == last.id)
        #expect(model.nextHomeworkProblem == nil)
        model.startNextProblem()
        #expect(model.problem.id == last.id, "最后一道，点了也不换")

        let unsaved = ProblemEditorModel(homework: model.homework)
        unsaved.switchMode(to: .solve)
        #expect(!unsaved.isHomeworkProblem)
        #expect(unsaved.nextHomeworkProblem == nil)
    }

    @Test("做题时点“上一题”回到前一道，从摆好的局面开始；没拍全的照样开始，提示补子")
    func previousProblem() {
        let model = solvingFirstOfPage()
        model.startNextProblem()
        model.startNextProblem()
        let eighth = saved("第 35 页第 8 题", in: model.homework!)
        #expect(model.previousHomeworkProblem?.id == eighth.id)
        model.tap(Point(0, 0))
        #expect(model.canUndo)

        model.startPreviousProblem()
        #expect(model.mode == .solve)
        #expect(model.problem.id == eighth.id)
        #expect(model.position == eighth.problem.startPosition, "从摆好的局面开始，第 9 题下的子不带过来")
        #expect(!model.canUndo)
        #expect(model.message == EditorMessage(text: "第 35 页第 8 题没拍全，缺的部分先回“摆题”照着书补上", tone: .warning))

        model.startPreviousProblem()
        #expect(model.problem.id == saved("第 35 页第 7 题", in: model.homework!).id)
        #expect(model.message == EditorMessage(text: "开始做第 35 页第 7 题", tone: .info))
    }

    @Test("最早存的那道没有上一题；手摆的题存进作业本以后也有上一题、下一题，没有题目名的提示“开始做上一题”")
    func previousProblemAtStart() {
        let homework = HomeworkStore(directory: directory)
        // 手摆一道没起题目名的题。不传题目时默认是例题，有题目名。
        let manual = ProblemEditorModel(problem: Problem(), homework: homework)
        manual.tap(Point(3, 3))
        manual.saveProblem()
        manual.switchMode(to: .solve)
        #expect(manual.isHomeworkProblem)
        #expect(manual.previousHomeworkProblem == nil)

        // 后拍的一页只有一道题，直接进摆题。
        let model = ProblemEditorModel(homework: homework)
        model.show(page([diagram(id: 0, number: 7)]), from: photo)
        model.switchMode(to: .solve)
        let seventh = model.problem.id
        #expect(model.previousHomeworkProblem?.id == manual.problem.id)

        model.startPreviousProblem()
        #expect(model.problem.id == manual.problem.id)
        #expect(model.message == EditorMessage(text: "开始做上一题", tone: .info))
        #expect(model.previousHomeworkProblem == nil)
        model.startPreviousProblem()
        #expect(model.problem.id == manual.problem.id, "最早的那道，点了也不换")
        #expect(model.nextHomeworkProblem?.id == seventh)
    }

    @Test("做没拍全的题，下了子以后“没拍全”还在")
    func incompleteNoteWhileSolving() {
        let model = solvingFirstOfPage()
        #expect(!model.isIncompleteProblem)
        model.startNextProblem()
        #expect(model.isIncompleteProblem)
        model.tap(Point(0, 0))
        #expect(model.canUndo)
        #expect(model.isIncompleteProblem)
    }

    @Test("点“已经全了”去掉没拍全，改过的棋子一起存回作业本；只改棋子不去掉")
    func markComplete() {
        let model = ProblemEditorModel(homework: HomeworkStore(directory: directory))
        model.show(page([diagram(id: 0, number: 7), diagram(id: 1, number: 8, incomplete: true)]), from: photo)
        let eighth = saved("第 35 页第 8 题", in: model.homework!)
        model.load(eighth)
        #expect(model.isIncompleteProblem)

        let empty = Point(0, 18)
        model.select(.black)
        model.tap(empty)
        #expect(model.saveState == .modified)
        model.switchMode(to: .solve)
        model.switchMode(to: .setup)
        #expect(model.isIncompleteProblem, "改了子、存回去了，还是标着没拍全")

        model.tap(Point(1, 18))
        model.markComplete()
        #expect(!model.isIncompleteProblem)
        #expect(model.saveState == .saved)
        let reopened = HomeworkStore(directory: directory)[eighth.id]
        #expect(reopened?.isIncomplete == false)
        #expect(reopened?.problem.setup[Point(1, 18)] == .black, "按钮按下前改的子也存了")
        #expect(reopened?.page == 35 && reopened?.number == 8)
    }
}
