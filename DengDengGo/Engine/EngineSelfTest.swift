#if DEBUG
import Foundation
import GoCore
import GoVision

/// 开发时检查 KataGo 判题：用 `-engineSelfTest <作业照片路径>` 启动 App，
/// 识别照片上的每道题，打印引擎找到的正解和每一步用的时间，然后退出。
/// 模拟器里的 App 能直接读 Mac 上的文件，传绝对路径就行；真机上先用 `xcrun devicectl device copy to`
/// 把照片拷到 App 的 Documents，路径不以 / 开头时就到 Documents 里找。
/// 再加 `-engineProblem <题号>` 只看那一道，并打印加了外框的棋盘和引擎考虑的每一手；
/// `-engineVisits <次数>` 改每个局面算多少次（默认 400）。
enum EngineSelfTest {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-engineSelfTest"), index + 1 < arguments.count else { return }
        let path = arguments[index + 1]
        let photo = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
        Task.detached {
            await run(photo: photo)
            exit(0)
        }
    }

    private static func run(photo: URL) async {
        guard let engine = InProcessKataGo.shared else { return log("没有打包模型") }
        log("引擎：\(engine.name)")
        // 先量一下速度：空棋盘算 20 次要多久。
        let warm = ContinuousClock.now
        let empty = try? await engine.analyze(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 7.5, maxVisits: 20))
        log("空棋盘 20 次用时 \(ContinuousClock.now - warm)，黑领先 \(empty.map { String(format: "%.2f", $0.scoreLead) } ?? "?") 目")
        let timed = ContinuousClock.now
        let next = try? await engine.analyze(EngineQuery(board: Board(size: 19), firstPlayer: .black, moves: [Point(3, 3)], komi: 7.5, maxVisits: 50))
        log("再算 50 次用时 \(ContinuousClock.now - timed)，白领先 \(next.map { String(format: "%.2f", $0.scoreLead) } ?? "?") 目")
        guard let image = PhotoLoader.image(at: photo), let page = try? PageRecognizer.recognize(image) else {
            return log("照片识别失败：\(photo.path)")
        }
        log("\(photo.lastPathComponent)：\(page.diagrams.count) 道题 \(page.toPlay?.name ?? "?")先 \(page.goal?.name ?? "题型不明")")
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-engineProblem"), index + 1 < arguments.count, let number = Int(arguments[index + 1]) {
            guard let diagram = page.diagrams.first(where: { $0.number == number }) else { return log("没找到第 \(number) 题") }
            await inspect(page.problem(for: diagram), engine: engine)
            return
        }
        for diagram in page.diagrams where !diagram.isIncomplete {
            await playOut(page.problem(for: diagram), engine: engine)
        }
    }

    /// 按引擎的正解一直下到判"答对了"，打印手顺和每道题用的时间；第 7 题另外试一下错的 D2。
    private static func playOut(_ problem: Problem, engine: KataGoEngine) async {
        let solver = EngineSolver(problem: problem, engine: engine)
        if problem.title == "第 35 页第 7 题" {
            log("第 7 题下 D2：\(await solver.judge([Point(3, 17)]))")
        }
        let start = ContinuousClock.now
        var moves: [Point?] = []
        defer { log("\(problem.title)：\(name(moves)) 用时 \(ContinuousClock.now - start)") }
        for _ in 0..<8 {
            guard let move = await solver.correctMoves(moves).first else { return log("  找不到正解") }
            moves.append(move)
            let verdict = await solver.judge(moves)
            guard verdict == .correct else { return log("  最后一手：\(verdict)") }
            moves.append(await solver.reply(moves))
        }
        log("  下了 8 手还没做完")
    }

    /// 打印一道题加了外框的样子，以及做题方先下、停一手时引擎考虑的下法。
    private static func inspect(_ problem: Problem, engine: KataGoEngine) async {
        let arguments = ProcessInfo.processInfo.arguments
        let visits = arguments.firstIndex(of: "-engineVisits").flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 400
        let frame = TsumegoFrame(problem: problem)
        log("\(problem.title) 区域 \(frame.area) 贴目 \(frame.komi) 外框紧贴区域的颜色 \(TsumegoFrame.wallColor(for: problem).name)\n" + frame.board.diagram)
        var results: [EngineAnalysis] = []
        for moves in [[], [nil]] as [[Point?]] {
            let query = EngineQuery(board: frame.board, firstPlayer: problem.toPlay, moves: moves, komi: frame.komi, maxVisits: visits, avoid: frame.distantPoints(on: frame.board))
            guard let analysis = try? await engine.analyze(query) else { continue }
            results.append(analysis)
            log(moves.isEmpty ? "做题方先下：" : "做题方停一手、对方先下：")
            log("  根节点 胜率 \(String(format: "%.2f", analysis.winrate)) 领先 \(String(format: "%.1f", analysis.scoreLead))")
            for candidate in analysis.candidates.prefix(8) {
                log("  \(candidate.move.map { KataGoProtocol.vertex($0, size: 19) } ?? "停") 访问 \(candidate.visits) 胜率 \(String(format: "%.2f", candidate.winrate)) 领先 \(String(format: "%.1f", candidate.scoreLead))")
            }
        }
        // 每个子：做题方先下和停一手时的归属（都从做题方看），差得多的就是要分死活的子。
        if results.count == 2 {
            let lines = problem.setup.occupiedPoints.map { p -> String in
                let i = p.y * 19 + p.x
                let first = results[0].ownership[i], passed = -results[1].ownership[i]
                return "\(KataGoProtocol.vertex(p, size: 19))\(problem.setup[p] == .black ? "黑" : "白") \(String(format: "%.2f", first))/\(String(format: "%.2f", passed))\(abs(first - passed) >= 0.6 ? " ★" : "")"
            }
            log("归属（先下/停一手）：" + lines.joined(separator: "  "))
        }
    }

    private static func name(_ moves: [Point?]) -> String {
        moves.map { $0.map { KataGoProtocol.vertex($0, size: 19) } ?? "停" }.joined(separator: " ")
    }

    private static func log(_ text: String) {
        print("[自测] \(text)")
        fflush(stdout)
    }
}
#endif
