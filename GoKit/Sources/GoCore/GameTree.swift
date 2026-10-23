/// 一手棋：落子或停一手。
public enum TreeMove: Hashable, Sendable {
    case play(Point)
    case pass

    public var point: Point? {
        if case .play(let p) = self { return p }
        return nil
    }
}

/// 变化树：从摆好的局面开始，每一手是一个节点，同一个局面可以试几种下法。
/// 节点只追加不移动，删除变化时只是从父节点上摘掉。
public struct GameTree: Sendable {
    public struct Node: Sendable {
        public let id: Int
        public let parent: Int?
        /// 按试下的先后排列。
        public fileprivate(set) var children: [Int] = []
        /// 根节点没有这一手。
        public let move: TreeMove?
        public let position: Position
        public let captured: [Point]
        /// 重做时走的分支：最近一次走过的那个。
        fileprivate var preferredChild: Int?
    }

    private var nodes: [Node]
    public private(set) var currentID: Int

    public init(root: Position) {
        nodes = [Node(id: 0, parent: nil, move: nil, position: root, captured: [])]
        currentID = 0
    }

    public static let rootID = 0

    public subscript(id: Int) -> Node { nodes[id] }

    public var current: Node { nodes[currentID] }
    public var position: Position { current.position }

    /// 最后一手落子的位置，停一手或在根节点时为 nil。
    public var lastMove: Point? { current.move?.point }

    /// 从根节点到当前节点的路径，含两端。
    public var path: [Int] {
        var ids = [currentID]
        while let parent = nodes[ids[0]].parent { ids.insert(parent, at: 0) }
        return ids
    }

    /// 走出这一手的一方。根节点没有。
    public func mover(of id: Int) -> Stone? {
        guard let parent = nodes[id].parent else { return nil }
        return nodes[parent].position.toPlay
    }

    /// 在当前局面落子。已经试过同一手时直接走进那个变化，不重复建节点。
    @discardableResult
    public mutating func play(_ p: Point) throws(MoveError) -> MoveResult {
        if let existing = current.children.first(where: { nodes[$0].move == .play(p) }) {
            enter(existing)
            return MoveResult(position: nodes[existing].position, captured: nodes[existing].captured)
        }
        let result = try position.playing(p)
        append(move: .play(p), position: result.position, captured: result.captured)
        return result
    }

    public mutating func pass() {
        if let existing = current.children.first(where: { nodes[$0].move == .pass }) {
            enter(existing)
            return
        }
        append(move: .pass, position: position.passing(), captured: [])
    }

    public var canUndo: Bool { current.parent != nil }
    public var canRedo: Bool { !current.children.isEmpty }

    public mutating func undo() {
        guard let parent = current.parent else { return }
        currentID = parent
    }

    /// 重做时会走进的那个节点。
    public var redoTarget: Int? { current.preferredChild ?? current.children.first }

    public mutating func redo() {
        guard let next = redoTarget else { return }
        currentID = next
    }

    public mutating func goToRoot() {
        currentID = Self.rootID
    }

    /// 跳到某个节点，并把路上的分支都记成重做时要走的分支。
    public mutating func go(to id: Int) {
        currentID = id
        var child = id
        while let parent = nodes[child].parent {
            nodes[parent].preferredChild = child
            child = parent
        }
    }

    /// 删掉某个变化（含它后面的所有手）。当前节点在里面时退回到它的父节点。根节点不能删。
    public mutating func deleteVariation(_ id: Int) {
        guard let parent = nodes[id].parent else { return }
        let onPath = path.contains(id)
        nodes[parent].children.removeAll { $0 == id }
        if nodes[parent].preferredChild == id {
            nodes[parent].preferredChild = nodes[parent].children.last
        }
        if onPath { currentID = parent }
    }

    private mutating func enter(_ id: Int) {
        nodes[currentID].preferredChild = id
        currentID = id
    }

    private mutating func append(move: TreeMove, position: Position, captured: [Point]) {
        let id = nodes.count
        nodes.append(Node(id: id, parent: currentID, move: move, position: position, captured: captured))
        nodes[currentID].children.append(id)
        enter(id)
    }
}
