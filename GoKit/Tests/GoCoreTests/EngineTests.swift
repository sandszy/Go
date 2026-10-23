import Foundation
import Testing
@testable import GoCore

/// 假的 KataGo：收到请求后按 respond 回一行。
final class FakeTransport: KataGoTransport, @unchecked Sendable {
    var respond: (_ request: [String: Any]) -> String
    private var onLine: (@Sendable (String) -> Void)?
    private(set) var requests: [[String: Any]] = []

    init(respond: @escaping (_ request: [String: Any]) -> String) { self.respond = respond }

    func start(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func send(_ line: String) {
        let request = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        requests.append(request)
        let reply = respond(request)
        DispatchQueue.global().async { [onLine] in onLine?(reply) }
    }
}

@Suite("KataGo 协议")
struct KataGoProtocolTests {
    @Test("坐标：左上角是 A19，跳过 I")
    func vertices() {
        #expect(KataGoProtocol.vertex(Point(0, 0), size: 19) == "A19")
        #expect(KataGoProtocol.vertex(Point(8, 18), size: 19) == "J1")
        #expect(KataGoProtocol.point("J1", size: 19) == Point(8, 18))
        #expect(KataGoProtocol.point("t19", size: 19) == Point(18, 0))
        #expect(KataGoProtocol.point("I5", size: 19) == nil)
    }

    @Test("请求里有摆好的子、轮流的手顺和停一手")
    func request() throws {
        var board = Board(size: 19)
        board[Point(3, 15)] = .black
        let query = EngineQuery(board: board, firstPlayer: .white, moves: [Point(15, 3), nil], komi: 0.5, maxVisits: 10)
        let json = try JSONSerialization.jsonObject(with: Data(KataGoProtocol.request(id: "7", query: query).utf8)) as! [String: Any]
        #expect(json["initialStones"] as? [[String]] == [["B", "D4"]])
        #expect(json["moves"] as? [[String]] == [["W", "Q16"], ["B", "pass"]])
        #expect(json["initialPlayer"] as? String == "W")
        #expect(query.toPlay == .white)
    }

    @Test("结果按 order 排，pass 变成 nil，搜索中途的结果不算")
    func parse() async throws {
        let transport = FakeTransport { request in
            let id = request["id"] as! String
            return #"{"id":"\#(id)","moveInfos":[{"move":"pass","order":1,"visits":3,"winrate":0.4,"scoreLead":-1},{"move":"C3","order":0,"visits":90,"winrate":0.9,"scoreLead":12.5}],"rootInfo":{"winrate":0.88,"scoreLead":12},"ownership":[0.5,-1]}"#
        }
        let engine = KataGoEngine(transport: transport)
        let analysis = try await engine.analyze(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10))
        #expect(analysis.candidates.map(\.move) == [Point(2, 16), nil])
        #expect(analysis.scoreLead == 12)
        #expect(analysis.ownership == [0.5, -1])
        #expect(KataGoProtocol.parse(#"{"id":"1","isDuringSearch":true,"moveInfos":[]}"#) == nil)
    }

    @Test("请求带上优先级；不给就不写")
    func priority() throws {
        func json(_ query: EngineQuery) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(KataGoProtocol.request(id: "1", query: query).utf8)) as! [String: Any]
        }
        let plain = try json(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10))
        #expect(plain["priority"] == nil)
        let guessed = try json(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10, priority: -1))
        #expect(guessed["priority"] as? Int == -1)
    }

    @Test("不用的请求让引擎停下，等着的一方收到失败")
    func terminate() async throws {
        // 这个假引擎只回停下的命令：被停下的请求回一行空结果。
        let transport = FakeTransport { request in
            guard request["action"] as? String == "terminate", let id = request["terminateId"] as? String else { return "{}" }
            return #"{"id":"\#(id)","isDuringSearch":false,"noResults":true}"#
        }
        let engine = KataGoEngine(transport: transport)
        let task = Task { try await engine.analyze(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10)) }
        while transport.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: EngineError.self) { try await task.value }
        #expect(transport.requests.last?["terminateId"] as? String == transport.requests.first?["id"] as? String)
    }

    @Test("引擎报错时请求失败")
    func error() async {
        let engine = KataGoEngine(transport: FakeTransport { request in
            #"{"id":"\#(request["id"] as! String)","error":"bad"}"#
        })
        await #expect(throws: EngineError.self) {
            try await engine.analyze(EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10))
        }
    }
}

/// 假引擎：按手数回答固定的分析。
struct ScriptedEngine: GoEngine {
    var answer: @Sendable (EngineQuery) -> EngineAnalysis
    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { answer(query) }
}

/// 记下收到的每个请求，再交给 answer 回答。
final class RecordingEngine: GoEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [EngineQuery] = []
    private let answer: @Sendable (EngineQuery) -> EngineAnalysis

    init(answer: @escaping @Sendable (EngineQuery) -> EngineAnalysis) { self.answer = answer }

    var queries: [EngineQuery] { lock.withLock { recorded } }

    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
        lock.withLock { recorded.append(query) }
        return answer(query)
    }

    /// 等到收到满足条件的请求，最多等一秒。
    func waitFor(_ condition: (EngineQuery) -> Bool) async -> EngineQuery? {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if let query = queries.first(where: condition) { return query }
            await Task.yield()
        }
        return nil
    }
}

/// 一算就报错的引擎，用来确认没问引擎。
struct FailingEngine: GoEngine {
    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { throw .failed("不该问引擎") }
}

@Suite("引擎打分")
struct EngineSolverTests {
    private let e2 = Point(4, 17)
    private let d2 = Point(3, 17)
    private let f1 = Point(5, 18)

    private func analysis(_ score: Double, best: Point?) -> EngineAnalysis {
        EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: [])
    }

    /// 开始时黑棋（做题方）最好能领先 10 目；E2 保持领先，D2 让白棋反过来领先。
    private func solver() -> EngineSolver {
        let e2 = e2, d2 = d2, f1 = f1
        return EngineSolver(problem: .sample, engine: ScriptedEngine { query in
            switch query.moves {
            case []: return analysis(10, best: e2)
            case [e2]: return analysis(-10, best: f1)
            case [d2]: return analysis(5, best: e2)
            case [e2, f1]: return analysis(10, best: Point(2, 17))
            case [e2, f1, Point(2, 17)]: return analysis(-10.5, best: nil)
            default: return analysis(0, best: nil)
            }
        })
    }

    @Test("下在引擎最想下的地方得 0 目，对方应在引擎最想下的地方")
    func scoreBest() async {
        let solver = solver()
        #expect(await solver.score([e2]) == .loss(0))
        #expect(await solver.reply([e2]) == f1)
    }

    @Test("亏几目就是几目：开头黑领先 10 目，D2 以后白领先 5 目，亏 15 目")
    func scoreLoss() async {
        #expect(await solver().score([d2]) == .loss(15))
    }

    @Test("算出来比最好的一手还好时，算 0 目")
    func neverPositive() async {
        let e2 = e2
        let solver = EngineSolver(problem: .sample, engine: ScriptedEngine { query in
            query.moves.isEmpty ? self.analysis(10, best: e2) : self.analysis(-12, best: nil)
        })
        #expect(await solver.score([e2]) == .loss(0))
    }

    @Test("下到题目区域外面不打分，不问引擎（引擎那边那里是外框，不认这一手）")
    func outsideArea() async {
        let solver = EngineSolver(problem: .sample, engine: FailingEngine())
        #expect(solver.isOutside(Point(0, 0)))
        #expect(!solver.isOutside(e2))
        #expect(await solver.score([Point(0, 0)]) == .outside)
        #expect(await solver.score([e2]) == .unknown)
    }

    @Test("每个局面按档位算多少次，中途换档从下一个局面开始用")
    func depth() async {
        let e2 = e2, f1 = f1
        let engine = RecordingEngine { query in
            query.moves.isEmpty ? self.analysis(10, best: e2) : self.analysis(-10, best: f1)
        }
        let solver = EngineSolver(problem: .sample, engine: engine, depth: .quick)
        _ = await solver.score([e2])
        #expect(engine.queries.allSatisfy { $0.maxVisits == EngineDepth.quick.visits })

        await solver.setDepth(.deep)
        _ = await solver.reply([e2, f1, Point(2, 17)])
        #expect(engine.queries.last?.maxVisits == EngineDepth.deep.visits)
    }

    @Test("轮到孩子时，猜孩子会下引擎最想下的几手，用低优先级提前算好")
    func guesses() async {
        let e2 = e2, d2 = d2
        let engine = RecordingEngine { query in
            guard query.moves.isEmpty else { return self.analysis(0, best: nil) }
            // 区域外的 A19 和次数太少的 C2 不猜。
            return EngineAnalysis(candidates: [
                .init(move: e2, visits: 100, winrate: 0.5, scoreLead: 10),
                .init(move: Point(0, 0), visits: 50, winrate: 0.5, scoreLead: 9),
                .init(move: d2, visits: 40, winrate: 0.5, scoreLead: 8),
                .init(move: Point(2, 17), visits: 5, winrate: 0.5, scoreLead: 1),
            ], winrate: 0.5, scoreLead: 10, ownership: [])
        }
        let solver = EngineSolver(problem: .sample, engine: engine)
        await solver.prepare([])
        #expect(await engine.waitFor { $0.moves == [d2] }?.priority == -1)
        #expect(await engine.waitFor { $0.moves == [e2] }?.priority == -1)
        #expect(!engine.queries.contains { $0.moves == [Point(0, 0)] || $0.moves == [Point(2, 17)] })
        // 孩子下了猜中的那手，直接用算好的结果，不再问引擎。
        let count = engine.queries.count
        _ = await solver.score([e2])
        #expect(engine.queries.count == count)
    }

    @Test("白方的手也能打分，从白方来看")
    func otherSide() async {
        let e2 = e2, f1 = f1, c2 = Point(2, 17)
        let solver = EngineSolver(problem: .sample, engine: ScriptedEngine { query in
            switch query.moves {
            case [e2]: return self.analysis(-10, best: f1)   // 轮到白，白最好落后 10 目
            case [e2, f1]: return self.analysis(10, best: c2)
            case [e2, c2]: return self.analysis(13, best: f1)   // 白下 C2，黑领先 13 目：白亏 3 目
            default: return self.analysis(10, best: e2)
            }
        })
        #expect(await solver.score([e2, f1]) == .loss(0))
        #expect(await solver.score([e2, c2]) == .loss(3))
    }

    @Test("第一手以后，双方只在要分死活的那块棋旁边一路以内下")
    func searchNearKeyStones() async {
        let key = Point(2, 15)   // 第 7 题里的一个黑子，和 (3, 15)、(4, 15) 连成一块
        let e2 = e2, f1 = f1
        @Sendable func ownership(_ value: Double) -> [Double] {
            var values = [Double](repeating: 0, count: 361)
            values[key.y * 19 + key.x] = value
            return values
        }
        // 黑先下这块棋活（+0.9），黑停一手就死（从白看 +0.9），所以是要分死活的子。
        let engine = RecordingEngine { query in
            switch query.moves {
            case []: EngineAnalysis(candidates: [.init(move: e2, visits: 100, winrate: 0.9, scoreLead: 10)], winrate: 0.9, scoreLead: 10, ownership: ownership(0.9))
            case [nil]: EngineAnalysis(candidates: [.init(move: e2, visits: 100, winrate: 0.9, scoreLead: 10)], winrate: 0.9, scoreLead: 10, ownership: ownership(0.9))
            default: EngineAnalysis(candidates: [.init(move: f1, visits: 100, winrate: 0.1, scoreLead: -10)], winrate: 0.1, scoreLead: -10, ownership: ownership(-0.9))
            }
        }
        let solver = EngineSolver(problem: .sample, engine: engine)
        await solver.prepare([])
        _ = await solver.score([e2])
        await solver.prepare([e2, f1])
        let avoid = await engine.waitFor { $0.moves == [e2, f1] }?.avoid ?? []
        #expect(avoid.contains(Point(2, 13)), "离这块棋两路，开头能下，第一手以后不下")
        #expect(!avoid.contains(Point(2, 14)), "紧挨着这块棋，能下")
    }

    @Test("引擎出错时算不出来")
    func failure() async {
        struct Broken: GoEngine {
            func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { throw .unavailable("没有模型") }
        }
        #expect(await EngineSolver(problem: .sample, engine: Broken()).score([e2]) == .unknown)
    }
}

@Suite("引擎搜索范围")
struct EngineSearchAreaTests {
    @Test("请求里双方都避开离棋子很远的空点")
    func avoidMoves() throws {
        let query = EngineQuery(board: Board(size: 19), firstPlayer: .black, komi: 6.5, maxVisits: 10, avoid: [Point(0, 0)])
        let json = try JSONSerialization.jsonObject(with: Data(KataGoProtocol.request(id: "1", query: query).utf8)) as! [String: Any]
        let avoid = try #require(json["avoidMoves"] as? [[String: Any]])
        #expect(avoid.map { $0["player"] as? String } == ["B", "W"])
        #expect(avoid.first?["moves"] as? [String] == ["A19"])
    }

    @Test("棋子旁边两路以内的空点能下，远处的空点不下（按吃子题摆，题目区域是印出来的那一大块）")
    func distantPoints() {
        var problem = Problem.sample
        problem.goal = .capture
        let frame = TsumegoFrame(problem: problem)
        let far = Set(frame.distantPoints(on: frame.board))
        #expect(!far.contains(Point(4, 17)))   // E2，正解
        #expect(far.contains(Point(0, frame.area.minY)))   // 区域左上角，离棋子很远
    }
}
