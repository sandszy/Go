/// 棋子颜色。
public enum Stone: String, Codable, Hashable, Sendable, CaseIterable {
    case black
    case white

    public var opponent: Stone { self == .black ? .white : .black }

    /// 界面上显示的名称："黑"或"白"。
    public var name: String { self == .black ? "黑" : "白" }
}

/// 棋盘上的交叉点。x 是从左往右的列，y 是从上往下的行，都从 0 开始。
public struct Point: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "(\(x), \(y))" }
}
