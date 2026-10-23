/// 引擎每一步想多深：每个局面算多少次。想得越深判得越准，孩子等得也越久。
/// 不限时间，算满次数为止。孩子想的时候引擎会先猜着算，猜中了孩子下完马上就应。
public enum EngineDepth: String, CaseIterable, Sendable {
    case quick
    case standard
    case deep

    public var name: String {
        switch self {
        case .quick: "快"
        case .standard: "标准"
        case .deep: "深"
        }
    }

    /// 给家长看的说明。
    public var detail: String {
        switch self {
        case .quick: "最快，难题可能判不准"
        case .standard: "快慢和准确兼顾"
        case .deep: "想得最久，判得最准"
        }
    }

    /// 每个局面最多算多少次。
    public var visits: Int {
        switch self {
        case .quick: 100
        case .standard: 200
        case .deep: 400
        }
    }
}
