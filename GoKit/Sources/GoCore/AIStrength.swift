/// 对弈时 AI 让多少。KataGo 全力下，初学的孩子一手都赢不了，所以要故意放水。
/// 办法借鉴 KaTrain：每手从能下的点里随机抽几个，下其中 KataGo 第一感觉最想下的那个，抽得越少越弱。
public enum AIStrength: String, CaseIterable, Sendable {
    case beginner
    case novice
    case full

    public var name: String {
        switch self {
        case .beginner: "入门"
        case .novice: "初级"
        case .full: "全力"
        }
    }

    /// 给家长看的说明。
    public var detail: String {
        switch self {
        case .beginner: "入门：AI 让很多，适合刚学"
        case .novice: "初级：AI 让一些"
        case .full: "全力：AI 不让，按思考深度尽力下"
        }
    }

    /// 每手随机抽几个点。全力不抽，下 KataGo 最好的一手。
    public var picks: Int? {
        switch self {
        case .beginner: 5
        case .novice: 15
        case .full: nil
        }
    }
}
