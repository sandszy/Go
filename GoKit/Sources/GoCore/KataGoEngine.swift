import Foundation

/// 和 KataGo 分析引擎（analysis 命令）之间一行一行收发 JSON 的通道。
/// App 里是同一进程中跑的 KataGo，测试里可以换成假的。
public protocol KataGoTransport: Sendable {
    /// 开始收引擎的输出，每次一行。只调一次。
    func start(onLine: @escaping @Sendable (String) -> Void)
    func send(_ line: String)
}

/// 通过 KataGo 的 analysis JSON 协议分析局面。同时可以有好几个请求在算，按 id 对上结果。
public final class KataGoEngine: GoEngine, @unchecked Sendable {
    private let transport: any KataGoTransport
    private let lock = NSLock()
    private var nextID = 0
    private var waiting: [String: CheckedContinuation<EngineAnalysis, any Error>] = [:]
    private var sizes: [String: Int] = [:]

    public init(transport: any KataGoTransport) {
        self.transport = transport
        transport.start { [weak self] line in self?.receive(line) }
    }

    public func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let id: String = lock.withLock {
                    nextID += 1
                    let id = String(nextID)
                    waiting[id] = continuation
                    sizes[id] = query.board.size
                    return id
                }
                transport.send(KataGoProtocol.request(id: id, query: query))
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    private func receive(_ line: String) {
        guard let response = KataGoProtocol.parse(line) else { return }
        switch response {
        case .analysis(let id, let json):
            guard let (continuation, size) = take(id) else { return }
            if let analysis = KataGoProtocol.analysis(from: json, size: size) {
                continuation.resume(returning: analysis)
            } else {
                continuation.resume(throwing: EngineError.failed("看不懂引擎的结果"))
            }
        case .error(let id?, let message):
            take(id)?.0.resume(throwing: EngineError.failed(message))
        case .error(nil, let message):
            // 没有 id 的错误对不上是哪个请求，说明引擎整个出了问题，让所有等着的都失败。
            let all = lock.withLock {
                defer { waiting = [:]; sizes = [:] }
                return Array(waiting.values)
            }
            for continuation in all { continuation.resume(throwing: EngineError.failed(message)) }
        }
    }

    private func take(_ id: String) -> (CheckedContinuation<EngineAnalysis, any Error>, Int)? {
        lock.withLock {
            guard let continuation = waiting.removeValue(forKey: id), let size = sizes.removeValue(forKey: id) else { return nil }
            return (continuation, size)
        }
    }
}

/// KataGo analysis 协议的请求和结果格式。坐标用 GTP 写法：列是字母（跳过 I），行从下往上数。
public enum KataGoProtocol {
    enum Response {
        case analysis(id: String, json: [String: Any])
        case error(id: String?, message: String)
    }

    static func request(id: String, query: EngineQuery) -> String {
        let size = query.board.size
        let stones: [[String]] = query.board.occupiedPoints.map { p in
            [color(query.board[p]!), vertex(p, size: size)]
        }
        var player = query.firstPlayer
        var moves: [[String]] = []
        for move in query.moves {
            moves.append([color(player), move.map { vertex($0, size: size) } ?? "pass"])
            player = player.opponent
        }
        let object: [String: Any] = [
            "id": id,
            "initialStones": stones,
            "moves": moves,
            "initialPlayer": color(query.firstPlayer),
            "rules": "japanese",
            "komi": query.komi,
            "boardXSize": size,
            "boardYSize": size,
            "maxVisits": query.maxVisits,
            "includeOwnership": true,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// 只关心最终结果和错误；警告、搜索中途的结果都跳过。
    static func parse(_ line: String) -> Response? {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let id = json["id"] as? String
        if let message = json["error"] as? String { return .error(id: id, message: message) }
        guard let id, json["moveInfos"] != nil, json["isDuringSearch"] as? Bool != true else { return nil }
        return .analysis(id: id, json: json)
    }

    static func analysis(from json: [String: Any], size: Int) -> EngineAnalysis? {
        guard let root = json["rootInfo"] as? [String: Any],
              let infos = json["moveInfos"] as? [[String: Any]]
        else { return nil }
        let candidates: [EngineAnalysis.Candidate] = infos
            .sorted { ($0["order"] as? Int ?? .max) < ($1["order"] as? Int ?? .max) }
            .compactMap { info in
                guard let move = info["move"] as? String,
                      let visits = info["visits"] as? Int,
                      let winrate = number(info["winrate"]),
                      let scoreLead = number(info["scoreLead"])
                else { return nil }
                if move.lowercased() == "pass" {
                    return .init(move: nil, visits: visits, winrate: winrate, scoreLead: scoreLead)
                }
                guard let point = point(move, size: size) else { return nil }
                return .init(move: point, visits: visits, winrate: winrate, scoreLead: scoreLead)
            }
        guard let winrate = number(root["winrate"]), let scoreLead = number(root["scoreLead"]) else { return nil }
        let ownership = (json["ownership"] as? [Any])?.compactMap(number) ?? []
        return EngineAnalysis(candidates: candidates, winrate: winrate, scoreLead: scoreLead, ownership: ownership)
    }

    public static func vertex(_ p: Point, size: Int) -> String {
        Coordinates.columnLabel(p.x) + Coordinates.rowLabel(p.y, size: size)
    }

    static func point(_ vertex: String, size: Int) -> Point? {
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        guard let first = vertex.uppercased().first, let x = letters.firstIndex(of: first),
              let row = Int(vertex.dropFirst()), (1...size).contains(row), x < size
        else { return nil }
        return Point(x, size - row)
    }

    private static func color(_ stone: Stone) -> String { stone == .black ? "B" : "W" }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
