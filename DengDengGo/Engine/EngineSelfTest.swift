#if DEBUG
import Foundation
import GoCore
import GoVision

/// 开发时检查 KataGo 判题：用 `-engineSelfTest <作业照片路径>` 启动 App，
/// 识别照片上的每道题，打印引擎找到的正解和每一步用的时间，然后退出。
/// 模拟器里没有引擎，要在真机上跑：照片先用 `xcrun devicectl device copy to` 拷到 App 的 Documents，
/// 路径不以 / 开头时就到 Documents 里找。
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
        guard let image = PhotoLoader.image(at: photo), let page = try? PageRecognizer.recognize(image) else {
            return log("照片识别失败：\(photo.path)")
        }
        for diagram in page.diagrams {
            await playOut(page.problem(for: diagram), engine: engine)
        }
    }

    /// 按引擎的正解一直下到判"答对了"，打印手顺和每道题用的时间；第 7 题另外试一下错的 D2。
    private static func playOut(_ problem: Problem, engine: KataGoEngine) async {
        let solver = EngineSolver(problem: problem, engine: engine)
        if problem.title.hasSuffix("第 7 题") {
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

    private static func name(_ moves: [Point?]) -> String {
        moves.map { $0.map { KataGoProtocol.vertex($0, size: 19) } ?? "停" }.joined(separator: " ")
    }

    private static func log(_ text: String) {
        print("[自测] \(text)")
        fflush(stdout)
    }
}
#endif
