/// 判题用的目标：谁要吃谁。吃子、逃子、对杀题都归结成"吃子方能不能吃掉目标块"。
public struct Objective: Hashable, Sendable {
    /// 做题的一方。
    public var player: Stone
    /// 要吃子的一方：吃子、对杀题是做题方，逃子题是对方。
    public var attacker: Stone
    /// 要被吃的块，每块记一个子。吃掉其中任意一块，吃子方就成功了。
    public var targets: [Point]
    /// 吃子方自己不能被吃的块，每块记一个子。对杀时就是自己被紧气的那块。
    public var guards: [Point]
    /// 目标块的气都不少于这个数，就算逃出去了。nil 表示不按气数判断。
    public var escapeLiberties: Int?

    public var defender: Stone { attacker.opponent }

    public init(player: Stone, attacker: Stone, targets: [Point], guards: [Point] = [], escapeLiberties: Int? = nil) {
        self.player = player
        self.attacker = attacker
        self.targets = targets
        self.guards = guards
        self.escapeLiberties = escapeLiberties
    }

    /// 根据题目目标和摆好的棋子推断。题目目标没设或暂不支持（连接、切断、做活、杀棋）时返回 nil。
    public static func infer(for problem: Problem) -> Objective? {
        let board = problem.setup
        let me = problem.toPlay
        switch problem.goal {
        case .capture:
            let targets = weakestGroups(of: me.opponent, among: board.groups, on: board)
            guard !targets.isEmpty else { return nil }
            return Objective(player: me, attacker: me, targets: anchors(of: targets), escapeLiberties: 4)

        case .escape:
            let targets = weakestGroups(of: me, among: board.groups, on: board)
            guard !targets.isEmpty else { return nil }
            return Objective(player: me, attacker: me.opponent, targets: anchors(of: targets), escapeLiberties: 4)

        case .capturingRace:
            // 自己贴着对方、气最少的块是要保住的；贴着它的对方块里气最少的是要吃的。
            let inContact = board.groups.filter { group in
                board[group.first!] == me && !board.neighborGroups(of: group, color: me.opponent).isEmpty
            }
            let guards = weakestGroups(of: me, among: inContact, on: board)
            var opponents: [Set<Point>] = []
            for guardGroup in guards {
                for group in board.neighborGroups(of: guardGroup, color: me.opponent) where !opponents.contains(group) {
                    opponents.append(group)
                }
            }
            let targets = weakestGroups(of: me.opponent, among: opponents, on: board)
            guard !guards.isEmpty, !targets.isEmpty else { return nil }
            return Objective(player: me, attacker: me, targets: anchors(of: targets), guards: anchors(of: guards))

        case .connect, .cut, .live, .kill, nil:
            return nil
        }
    }

    /// 某种颜色的块里气最少的那些（气数超过 maxLiberties 的不算）。
    private static func weakestGroups(
        of color: Stone,
        among groups: [Set<Point>],
        on board: Board,
        maxLiberties: Int = 4
    ) -> [Set<Point>] {
        let candidates = groups
            .filter { board[$0.first!] == color }
            .map { (group: $0, liberties: board.liberties(of: $0).count) }
            .filter { $0.liberties <= maxLiberties }
        guard let fewest = candidates.map(\.liberties).min() else { return [] }
        return candidates.filter { $0.liberties == fewest }.map(\.group)
    }

    /// 每块取最上、最左的一个子做标记，结果固定，方便测试。
    private static func anchors(of groups: [Set<Point>]) -> [Point] {
        groups
            .map { $0.min { ($0.y, $0.x) < ($1.y, $1.x) }! }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }
}
