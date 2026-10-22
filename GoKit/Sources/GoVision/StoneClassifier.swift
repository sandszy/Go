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

    static func classify(at center: (x: Double, y: Double), spacing s: Double, ink: InkMask) -> Reading {
        let fill = inkFraction(inDiskOf: s * 0.28, at: center, ink: ink)
        if fill >= 0.55 { return Reading(stone: .black, uncertain: false) }
        // 空点中间只有交叉的两条线，棋盘边的粗线交叉也不到四成；超过这个就可疑了。
        let suspicious = fill >= 0.45

        // 中心往四个方向伸出去的短线段上有没有网格线。白子里的数字只在正中间，避开中心就碰不到。
        let left = armInked(center, dx: -1, dy: 0, s: s, ink: ink)
        let right = armInked(center, dx: 1, dy: 0, s: s, ink: ink)
        let up = armInked(center, dx: 0, dy: -1, s: s, ink: ink)
        let down = armInked(center, dx: 0, dy: 1, s: s, ink: ink)
        if (left || right) && (up || down) {
            return Reading(stone: nil, uncertain: suspicious)
        }

        let ring = ringFraction(at: center, s: s, ink: ink)
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
    private static func armInked(_ c: (x: Double, y: Double), dx: Double, dy: Double, s: Double, ink: InkMask) -> Bool {
        let side = max(4, Int((s * 0.15).rounded()))
        var hits = 0
        for i in 0..<6 {
            let t = s * (0.18 + 0.044 * Double(i))
            let x = Int((c.x + dx * t).rounded()), y = Int((c.y + dy * t).rounded())
            func inked(_ offset: Int) -> Bool { dx != 0 ? ink[x, y + offset] : ink[x + offset, y] }
            let found = (-2...2).contains { offset in
                inked(offset) && !inked(offset - side) && !inked(offset + side)
            }
            if found { hits += 1 }
        }
        return hits >= 4
    }

    /// 在 0.38 到 0.52 个线距的圆环上，有多少个方向碰到了墨迹（白子的轮廓）。
    private static func ringFraction(at c: (x: Double, y: Double), s: Double, ink: InkMask) -> Double {
        let directions = 36
        var hits = 0
        for k in 0..<directions {
            let angle = Double(k) / Double(directions) * 2 * Double.pi
            var r = s * 0.38
            while r <= s * 0.52 {
                if ink[Int((c.x + cos(angle) * r).rounded()), Int((c.y + sin(angle) * r).rounded())] {
                    hits += 1
                    break
                }
                r += 1
            }
        }
        return Double(hits) / Double(directions)
    }
}
