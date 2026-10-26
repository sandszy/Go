import SwiftUI

/// 棋盘和棋子的配色，和 App 图标用同一套胡桃木 + 玻璃棋子的质感。
enum Theme {
    static let wood = Color(red: 0.87, green: 0.71, blue: 0.45)
    static let line = Color(red: 0.16, green: 0.11, blue: 0.06)

    /// 棋盘木纹，中心偏左上留一点高光，往边角压深，呼应图标的胡桃木底色。
    static let woodGradient = Gradient(stops: [
        .init(color: Color(red: 0.90, green: 0.75, blue: 0.52), location: 0.0),
        .init(color: Color(red: 0.83, green: 0.65, blue: 0.40), location: 0.35),
        .init(color: Color(red: 0.68, green: 0.50, blue: 0.29), location: 0.68),
        .init(color: Color(red: 0.52, green: 0.37, blue: 0.21), location: 0.88),
        .init(color: Color(red: 0.38, green: 0.26, blue: 0.15), location: 1.0),
    ])

    /// 黑子：中心留一块灰色平台而不是纯黑，边缘才压到近黑，避免像一颗反光小球。
    static let blackStoneGradient = Gradient(stops: [
        .init(color: Color(white: 0.33), location: 0.0),
        .init(color: Color(white: 0.24), location: 0.32),
        .init(color: Color(white: 0.13), location: 0.62),
        .init(color: Color(white: 0.05), location: 0.88),
        .init(color: Color(white: 0.015), location: 1.0),
    ])

    /// 白子：偏暖的米白，边缘微微泛黄褐，像长期把玩的蛤壳子。
    static let whiteStoneGradient = Gradient(stops: [
        .init(color: Color(red: 1.0, green: 0.99, blue: 0.97), location: 0.0),
        .init(color: Color(red: 0.97, green: 0.95, blue: 0.90), location: 0.42),
        .init(color: Color(red: 0.92, green: 0.88, blue: 0.80), location: 0.68),
        .init(color: Color(red: 0.85, green: 0.80, blue: 0.69), location: 0.88),
        .init(color: Color(red: 0.78, green: 0.73, blue: 0.60), location: 1.0),
    ])

    static let whiteStoneRim = Color(red: 0.47, green: 0.42, blue: 0.33)
    static let blackStoneRim = Color(white: 0.42)

    /// 模式切换条的木纹：线性对角渐变（不用径向），矮胖的长条里才不会出现突兀光斑；
    /// 比棋盘本身亮一些，像一块单独钉上去的木牌，不会被误认成棋盘的一部分。
    static let modeBarGradient = Gradient(stops: [
        .init(color: Color(red: 0.93, green: 0.81, blue: 0.60), location: 0.0),
        .init(color: Color(red: 0.84, green: 0.68, blue: 0.46), location: 0.5),
        .init(color: Color(red: 0.72, green: 0.55, blue: 0.34), location: 1.0),
    ])
    static let modeBarRim = line.opacity(0.3)

    /// 棋盘画框：摆题琥珀色、做题和对弈深青色，瞄一眼棋盘（不用看顶上的切换条）就知道现在是哪种模式，
    /// 免得忘记点"做题"还在摆题模式下落子。见需求说明 F1.7。
    static let setupFrame = Color(red: 0.82, green: 0.49, blue: 0.14)
    static let playFrame = Color(red: 0.10, green: 0.42, blue: 0.44)

    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
