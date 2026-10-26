import Foundation
import GoCore

/// 判断交叉点上是黑子、白子还是空：
/// 黑子中间是实心的墨；空点有网格线穿过中心；白子里面是空白，外面一圈有轮廓。
enum StoneClassifier {
    struct Reading {
        var stone: Stone?
        /// 三种特征都不明显，校对时要提醒看一眼。
        var uncertain: Bool
        /// 白子中间有墨迹，可能印着数字。
        var marked = false
    }

    /// onShadow：这个点压在书缝的阴影上。不认黑子；阴影的边会被当成白子的轮廓，要轮廓很完整才算白子。
    /// ridges：比两侧都暗的点（横线、竖线各一张）。照片晃了、线糊成浅灰的宽带时，墨迹图上没有线，这里还有。
    static func classify(
        at center: (x: Double, y: Double), spacing s: Double, ink: InkMask,
        ridges: (horizontal: InkMask, vertical: InkMask)? = nil, onShadow: Bool = false
    ) -> Reading {
        let fill = inkFraction(inDiskOf: s * 0.28, at: center, ink: ink)
        if fill >= 0.55 {
            // 压在书缝阴影上的不认黑子，留空：书页卷得厉害时，阴影又黑又宽，像一列黑子。宁可漏一颗，让家长照着书补。
            if onShadow { return Reading(stone: nil, uncertain: true) }
            // 黑子是圆的，横竖都有一个子那么宽。书缝的阴影是窄长的一条，铅笔印、橡皮屑比棋子小，都不是黑子。
            let reach = 0.33
            func inked(_ dx: Double, _ dy: Double) -> Bool {
                let x = Int((center.x + dx * s).rounded()), y = Int((center.y + dy * s).rounded())
                return (-1...1).contains { d in ink[x + d, y] || ink[x, y + d] }
            }
            if inked(-reach, 0) && inked(reach, 0) && inked(0, -reach) && inked(0, reach) {
                return Reading(stone: .black, uncertain: false)
            }
            return Reading(stone: nil, uncertain: true)
        }
        // 空点中间只有交叉的两条线，棋盘边的粗线交叉也不到四成；超过这个就可疑了。
        let suspicious = fill >= 0.45

        // 中心往四个方向伸出去的短线段上有没有网格线。白子里的数字只在正中间，避开中心就碰不到。
        let left = armInked(center, dx: -1, dy: 0, s: s, ink: ink, ridge: ridges?.horizontal)
        let right = armInked(center, dx: 1, dy: 0, s: s, ink: ink, ridge: ridges?.horizontal)
        let up = armInked(center, dx: 0, dy: -1, s: s, ink: ink, ridge: ridges?.vertical)
        let down = armInked(center, dx: 0, dy: 1, s: s, ink: ink, ridge: ridges?.vertical)
        if (left || right) && (up || down) {
            return Reading(stone: nil, uncertain: suspicious)
        }

        let (ring, shaded) = ringFraction(at: center, s: s, ink: ink)
        // 白子的轮廓是一圈细线，外面就是纸。书缝的阴影、照片边上的暗处是一大片，轮廓外面还是墨，不是白子。
        if shaded { return Reading(stone: nil, uncertain: true) }
        if onShadow {
            return ring >= 0.75 ? Reading(stone: .white, uncertain: true, marked: fill >= 0.04) : Reading(stone: nil, uncertain: true)
        }
        if ring >= 0.55 {
            return Reading(stone: .white, uncertain: suspicious, marked: fill >= 0.04)
        }
        // 一条线都没穿过中心，空点不会这样，只能是被白子盖住了。印得淡、或者网格和交叉点有点偏差时，
        // 轮廓只碰到一部分，有三成就算白子，但要提醒校对。
        if !(left || right || up || down) && ring >= 0.3 {
            return Reading(stone: .white, uncertain: true, marked: fill >= 0.04)
        }
        return Reading(stone: nil, uncertain: true)
    }

    private static func inkFraction(inDiskOf radius: Double, at c: (x: Double, y: Double), ink: InkMask) -> Double {
        let r = Int(radius.rounded(.up))
        var total = 0, inked = 0
        for dy in -r...r {
            for dx in -r...r where Double(dx * dx + dy * dy) <= radius * radius {
                total += 1
                if ink[Int(c.x.rounded()) + dx, Int(c.y.rounded()) + dy] { inked += 1 }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    /// 从 0.18 到 0.40 个线距取 6 个点，至少 4 个点附近（垂直方向 ±2 像素内）有细的墨迹就算有线。
    /// 要"细"：再往两边 0.15 个线距都是纸。照片里的网格和实际交叉点有一点偏差时，伸出去的短线段
    /// 会碰到旁边黑子的边，黑子是一大片墨，不算线；不然夹在黑子中间的白子会被当成空点。
    /// 线点图（ridge）上的点也算：手晃糊了的浅线在墨迹图上没有，线点图上有，它本身就是细的。
    private static func armInked(_ c: (x: Double, y: Double), dx: Double, dy: Double, s: Double, ink: InkMask, ridge: InkMask?) -> Bool {
        let side = max(4, Int((s * 0.15).rounded()))
        var hits = 0
        for i in 0..<6 {
            let t = s * (0.18 + 0.044 * Double(i))
            let x = Int((c.x + dx * t).rounded()), y = Int((c.y + dy * t).rounded())
            func inked(_ offset: Int) -> Bool { dx != 0 ? ink[x, y + offset] : ink[x + offset, y] }
            func onRidge(_ offset: Int) -> Bool { ridge.map { dx != 0 ? $0[x, y + offset] : $0[x + offset, y] } ?? false }
            let found = (-2...2).contains { offset in
                (inked(offset) && !inked(offset - side) && !inked(offset + side)) || onRidge(offset)
            }
            if found { hits += 1 }
        }
        return hits >= 4
    }

    /// 在 0.38 到 0.52 个线距的圆环上，有多少个方向碰到了墨迹（白子的轮廓）。
    /// shaded：斜方向上碰到的墨迹，四分之三以上往外到 0.7 个线距还是墨，那是一大片阴影，不是细细的轮廓。
    private static func ringFraction(at c: (x: Double, y: Double), s: Double, ink: InkMask) -> (fraction: Double, shaded: Bool) {
        let directions = 36
        var hits = 0, diagonal = 0, thick = 0
        for k in 0..<directions {
            let angle = Double(k) / Double(directions) * 2 * Double.pi
            func inked(_ r: Double) -> Bool { ink[Int((c.x + cos(angle) * r).rounded()), Int((c.y + sin(angle) * r).rounded())] }
            var r = s * 0.38
            while r <= s * 0.52 {
                if inked(r) {
                    hits += 1
                    // 斜着的方向上没有网格线，旁边的棋子也够不着 0.6 到 0.7 个线距；这里还是墨，就是一大片暗处。
                    if k % 9 >= 2 && k % 9 <= 7 {
                        diagonal += 1
                        if inked(s * 0.6) && inked(s * 0.65) && inked(s * 0.7) { thick += 1 }
                    }
                    break
                }
                r += 1
            }
        }
        return (Double(hits) / Double(directions), diagonal > 0 && thick * 4 >= diagonal * 3)
    }
}
