import Foundation

/// 一条网格线。横线是 y = a + b·x + c·(x - t0)²，竖线是 x = a + b·y + c·(y - t0)²；
/// b 是照片拍歪带来的斜率，c 是书页卷起来时线的弯曲（靠书缝的地方线会往上或往下弯）。
struct GridLine {
    var a: Double
    var b: Double
    /// 线的粗细（像素），棋盘边线比里面的线粗。
    var thickness: Double
    var c: Double = 0
    var t0: Double = 0

    func value(at t: Double) -> Double { a + b * t + c * (t - t0) * (t - t0) }
}

/// 照片里找到的一个棋盘图：横竖网格线和线距，坐标是工作图的像素。
struct DetectedGrid {
    var horizontal: [GridLine]
    var vertical: [GridLine]
    var spacing: Double
    var edges: DiagramEdges

    /// 第 row 条横线和第 column 条竖线的交点。
    func intersection(row: Int, column: Int) -> (x: Double, y: Double) {
        let h = horizontal[row], v = vertical[column]
        // 先按直线求，再来回代几次把弯曲算进去；线都差不多横平竖直，几次就收敛了。
        var x = (v.a + v.b * h.a) / (1 - v.b * h.b)
        var y = h.value(at: x)
        for _ in 0..<4 {
            x = v.value(at: y)
            y = h.value(at: x)
        }
        return (x, y)
    }

    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let corners = [(0, 0), (0, vertical.count - 1), (horizontal.count - 1, 0), (horizontal.count - 1, vertical.count - 1)]
            .map { intersection(row: $0.0, column: $0.1) }
        let margin = spacing * 0.6
        return (
            corners.map(\.x).min()! - margin, corners.map(\.y).min()! - margin,
            corners.map(\.x).max()! + margin, corners.map(\.y).max()! + margin
        )
    }
}

/// 在墨迹图里找棋盘图。思路：棋盘图是一大片互相连着的长直线，文字和题号没有长直线。
enum GridDetector {
    /// ridges 是线点图（`GrayImage.ridges`），线从它里面找。另外返回去掉的书缝、页边那些长线：认子时，压在书缝阴影上的点要小心。
    static func detect(in ink: InkMask, ridges: (horizontal: InkMask, vertical: InkMask)) -> (grids: [DetectedGrid], shadows: InkMask) {
        let width = ink.width
        let gap = lineGap(width: width)
        let lengths = (short: max(8, width / 120), long: max(24, width / 30))
        let horizontalRuns = ink.thinHorizontalRuns(minLengths: lengths, gap: gap, ridges: (ridges.horizontal, ridges.vertical))
        let verticalRuns = ink.thinVerticalRuns(minLengths: lengths, gap: gap, ridges: (ridges.vertical, ridges.horizontal))
        var longHorizontal = horizontalRuns.long, longVertical = verticalRuns.long
        let stray = removeStrayLines(&longHorizontal, &longVertical, reach: gap)
        let longLines = longHorizontal.union(longVertical)
        let shortHorizontal = horizontalRuns.short.subtracting(stray)
        let shortVertical = verticalRuns.short.subtracting(stray)

        // 撑大外框时不走书缝、页边那几条长线旁边：书缝的阴影一路连下去，会把外框撑到别处。
        let growInk = ink.subtracting(stray.dilated(by: gap + gap / 2))
        let grids = lineClusters(longLines, ink: growInk, horizontal: shortHorizontal, vertical: shortVertical).compactMap { box in
            fitGrid(in: box, ink: ink, horizontal: shortHorizontal, vertical: shortVertical)
        }
        return (grids, stray)
    }

    /// 书缝、页边、页码下面的横杠这些长线不是棋盘线，却会把棋盘图和别的东西（隔壁页、页码）连成一片，
    /// 或者被当成棋盘最边上的一条线。棋盘线每隔一格就和一条线交叉；这些线很长，却几乎不和别的线交叉：
    /// 一条都不交叉、比 3 格长的，或者只交叉两条、比 6 格长的，就是这种线，去掉。返回去掉的像素。
    static func removeStrayLines(_ horizontal: inout InkMask, _ vertical: inout InkMask, reach: Int) -> InkMask {
        let (hLabels, hBoxes) = components(horizontal)
        let (vLabels, vBoxes) = components(vertical)
        // 每条线和每条交叉线碰到的位置（沿着这条线的坐标）。细线碰到棋盘的粗边线时，细线的像素停在粗线外沿，
        // 离粗线中间还有几个像素，所以顺着线的方向往前多看 reach 个像素。
        var hCross = [[Int: Int]](repeating: [:], count: hBoxes.count)
        var vCross = [[Int: Int]](repeating: [:], count: vBoxes.count)
        let width = horizontal.width, height = horizontal.height
        for y in 0..<height {
            for x in 0..<width {
                let hl = hLabels[y * width + x]
                if hl >= 0 {
                    for dy in -1...1 {
                        for dx in -reach...reach {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                            let vl = vLabels[ny * width + nx]
                            if vl >= 0 {
                                if hCross[hl][vl] == nil { hCross[hl][vl] = nx }
                                if vCross[vl][hl] == nil { vCross[vl][hl] = y }
                            }
                        }
                    }
                }
                let vl = vLabels[y * width + x]
                if vl >= 0 {
                    for dy in -reach...reach {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                            let hl = hLabels[ny * width + nx]
                            if hl >= 0 {
                                if hCross[hl][vl] == nil { hCross[hl][vl] = x }
                                if vCross[vl][hl] == nil { vCross[vl][hl] = ny }
                            }
                        }
                    }
                }
            }
        }
        // 同一条交叉线断成了几段时，交叉的位置挨在一起，算一个。
        func positions(_ crossings: Dictionary<Int, Int>.Values) -> [Int] {
            var result: [Int] = []
            for p in crossings.sorted() where result.last.map({ p - $0 > 5 }) ?? true { result.append(p) }
            return result
        }
        let hPositions = hCross.map { positions($0.values) }
        let vPositions = vCross.map { positions($0.values) }
        func gaps(_ p: [Int]) -> [Double] { zip(p.dropFirst(), p).map { Double($0 - $1) } }
        // 整页的线距：交叉够多的线上，相邻交叉点的间隔。
        let cells = (hPositions + vPositions).filter { $0.count >= 3 }.compactMap { median(gaps($0)) }
        let pageCell = median(cells) ?? Double(max(width, height)) / 40
        func stray(_ box: Box, positions: [Int], isHorizontal: Bool) -> Bool {
            let (start, end) = isHorizontal ? (box.minX, box.maxX) : (box.minY, box.maxY)
            let length = Double(end - start + 1)
            if positions.count < 2 { return length > pageCell * 3 }
            return positions.count < 3 && length > pageCell * 6
        }
        let hStray = hBoxes.indices.map { stray(hBoxes[$0], positions: hPositions[$0], isHorizontal: true) }
        let vStray = vBoxes.indices.map { stray(vBoxes[$0], positions: vPositions[$0], isHorizontal: false) }
        var removed = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            if hLabels[i] >= 0 && hStray[hLabels[i]] { horizontal.bits[i] = false; removed[i] = true }
            if vLabels[i] >= 0 && vStray[vLabels[i]] { vertical.bits[i] = false; removed[i] = true }
        }
        return InkMask(width: width, height: height, bits: removed)
    }

    /// 连在一起的墨迹编号（八连通），返回每个像素的编号（-1 是纸）和每块的外框。
    static func components(_ mask: InkMask) -> (labels: [Int], boxes: [Box]) {
        let width = mask.width, height = mask.height
        var labels = [Int](repeating: -1, count: width * height)
        var boxes: [Box] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where mask.bits[start] && labels[start] < 0 {
            let label = boxes.count
            var box: Box = (Int.max, Int.max, 0, 0)
            labels[start] = label
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbor = ny * width + nx
                        if mask.bits[neighbor] && labels[neighbor] < 0 {
                            labels[neighbor] = label
                            stack.append(neighbor)
                        }
                    }
                }
            }
            boxes.append(box)
        }
        return (labels, boxes)
    }

    /// 判断"细线"时往两边看多远。要大于棋盘边粗线的一半宽，粗线才不会被当成黑子去掉。
    static func lineGap(width: Int) -> Int { max(4, width / 250) }

    typealias Box = (minX: Int, minY: Int, maxX: Int, maxY: Int)

    /// 把长直线按位置聚成一团一团，每团的外框可能是一个棋盘图。碰到照片边上的（隔壁页露出来的半个图）不要。
    /// 棋子摆得密时，被棋子挡住的那几行几列露不出长直线，外框只框住了一部分；给了 ink 时，
    /// 再顺着连在一起的墨迹（棋子都压在线上，整个棋盘图是连成一片的）把外框撑到整个图。
    /// 再给了 horizontal、vertical 时，先按长直线拟合一次网格量出线距，每边最多撑 5 个线距。
    static func lineClusters(_ lines: InkMask, ink: InkMask? = nil, horizontal: InkMask? = nil, vertical: InkMask? = nil) -> [Box] {
        let cell = max(4, lines.width / 250)
        // 隔大约半个线距也算连着：横线之间隔一个线距，棋子又会把竖线挡断。
        let reach = max(2, lines.width / 60 / cell)
        let columns = lines.width / cell + 1, rows = lines.height / cell + 1
        var occupied = [Bool](repeating: false, count: columns * rows)
        for y in 0..<lines.height {
            for x in 0..<lines.width where lines[x, y] {
                occupied[(y / cell) * columns + x / cell] = true
            }
        }

        var seen = [Bool](repeating: false, count: columns * rows)
        var boxes: [Box] = []
        for start in 0..<occupied.count where occupied[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0
            while let index = stack.popLast() {
                let cx = index % columns, cy = index / columns
                minX = min(minX, cx); maxX = max(maxX, cx)
                minY = min(minY, cy); maxY = max(maxY, cy)
                for dy in -reach...reach {
                    for dx in -reach...reach {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < columns, ny < rows else { continue }
                        let neighbor = ny * columns + nx
                        if occupied[neighbor] && !seen[neighbor] {
                            seen[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            boxes.append((minX: minX * cell, minY: minY * cell, maxX: min(lines.width - 1, (maxX + 1) * cell), maxY: min(lines.height - 1, (maxY + 1) * cell)))
        }

        let minSize = lines.width / 10
        let margin = cell * 2
        if let ink {
            // 只撑大起码有半个图大的团，零碎的线段（文字、页边）不管。
            boxes = mergeOverlapping(boxes).map { box in
                guard box.maxX - box.minX >= minSize / 2 && box.maxY - box.minY >= minSize / 2 else { return box }
                // 被棋子挡住的最多三四行；撑得比 5 个线距还远，就是顺着书缝的阴影连到别处去了。
                var reach: Int?
                if let horizontal, let vertical, let grid = fitGrid(in: box, ink: ink, horizontal: horizontal, vertical: vertical) {
                    reach = Int(grid.spacing * 5)
                }
                return grow(box, along: ink, reach: reach)
            }
        }
        return mergeOverlapping(boxes).filter { box in
            let touchesEdge = box.minX < margin || box.minY < margin || box.maxX > lines.width - margin || box.maxY > lines.height - margin
            return box.maxX - box.minX >= minSize && box.maxY - box.minY >= minSize && !touchesEdge
        }
    }

    /// 从框里的墨迹出发，把连着的墨迹都找出来，返回它们的外框。每边最多往外撑原来那么大（给了 reach 时再不超过 reach），
    /// 免得顺着阴影、页边一路连出去；撑到了上限或照片边上的那边说明连出去了，那边保持原样。
    /// 照片边上露出半截的隔壁题，长直线本身就碰到了照片边，在 lineClusters 里已经不要了，用不着靠撑大来认。
    static func grow(_ box: Box, along ink: InkMask, reach: Int? = nil) -> Box {
        let limitX = min(reach ?? .max, box.maxX - box.minX), limitY = min(reach ?? .max, box.maxY - box.minY)
        let limit: Box = (max(0, box.minX - limitX), max(0, box.minY - limitY),
                          min(ink.width - 1, box.maxX + limitX), min(ink.height - 1, box.maxY + limitY))
        let width = limit.maxX - limit.minX + 1
        var seen = [Bool](repeating: false, count: width * (limit.maxY - limit.minY + 1))
        var stack: [(Int, Int)] = []
        for y in box.minY...box.maxY {
            for x in box.minX...box.maxX where ink[x, y] {
                seen[(y - limit.minY) * width + (x - limit.minX)] = true
                stack.append((x, y))
            }
        }
        var found = box
        while let (x, y) = stack.popLast() {
            found = (min(found.minX, x), min(found.minY, y), max(found.maxX, x), max(found.maxY, y))
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= limit.minX, ny >= limit.minY, nx <= limit.maxX, ny <= limit.maxY, ink[nx, ny] else { continue }
                    let index = (ny - limit.minY) * width + (nx - limit.minX)
                    if !seen[index] {
                        seen[index] = true
                        stack.append((nx, ny))
                    }
                }
            }
        }
        // 撑到离照片边只有几个像素，也算撑到了照片边。
        let margin = lineGap(width: ink.width) * 2
        return (
            found.minX <= max(limit.minX, margin) ? box.minX : found.minX,
            found.minY <= max(limit.minY, margin) ? box.minY : found.minY,
            found.maxX >= min(limit.maxX, ink.width - 1 - margin) ? box.maxX : found.maxX,
            found.maxY >= min(limit.maxY, ink.height - 1 - margin) ? box.maxY : found.maxY
        )
    }

    /// 同一个棋盘图被拆成了几块时，它们的外框会重叠，合成一个。
    private static func mergeOverlapping(_ boxes: [Box]) -> [Box] {
        var merged = boxes
        var changed = true
        while changed {
            changed = false
            outer: for i in merged.indices {
                for j in merged.indices where j > i {
                    let a = merged[i], b = merged[j]
                    if a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY {
                        merged[i] = (min(a.minX, b.minX), min(a.minY, b.minY), max(a.maxX, b.maxX), max(a.maxY, b.maxY))
                        merged.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return merged
    }

    static func fitGrid(
        in box: Box,
        ink: InkMask,
        horizontal: InkMask,
        vertical: InkMask
    ) -> DetectedGrid? {
        let xRange = Double(box.minX)...Double(box.maxX)
        let yRange = Double(box.minY)...Double(box.maxY)
        let centerX = (xRange.lowerBound + xRange.upperBound) / 2
        let centerY = (yRange.lowerBound + yRange.upperBound) / 2

        // 横线像素 (x, y) 记成 (沿线方向的 x, 垂直方向的 y)，竖线反过来，两个方向用同一套办法。
        var rowPixels: [(t: Double, v: Double)] = []
        var columnPixels: [(t: Double, v: Double)] = []
        for y in box.minY...box.maxY {
            for x in box.minX...box.maxX {
                if horizontal[x, y] { rowPixels.append((Double(x), Double(y))) }
                if vertical[x, y] { columnPixels.append((Double(y), Double(x))) }
            }
        }
        let rowProjection = straightenedProjection(rowPixels, center: centerX, range: yRange)
        let columnProjection = straightenedProjection(columnPixels, center: centerY, range: xRange)
        var rowPeaks = peaks(rowProjection.counts).map { $0 + yRange.lowerBound }
        var columnPeaks = peaks(columnProjection.counts).map { $0 + xRange.lowerBound }
        guard max(rowPeaks.count, columnPeaks.count) >= 4, min(rowPeaks.count, columnPeaks.count) >= 2 else { return nil }

        let spacing = estimateSpacing(rowPeaks, columnPeaks)
        guard spacing > 6 else { return nil }
        // 书缝的阴影、页边这种线穿过整个外框，两头都远远伸出去；棋盘线最多伸出去半格。
        func passesThrough(_ position: Double, slope: Double, center: Double, along: ClosedRange<Double>, isColumn: Bool) -> Bool {
            // 书缝是弯的，往外推几格会偏开一点，左右各看 0.15 格。棋盘图之间空着两格左右，一路都是墨才算。
            let side = max(2, Int((spacing * 0.15).rounded()))
            func inked(_ t: Double) -> Bool {
                let v = position + slope * (t - center)
                return (-side...side).contains { d in isColumn ? ink[Int(v.rounded()) + d, Int(t.rounded())] : ink[Int(t.rounded()), Int(v.rounded()) + d] }
            }
            let steps = [1.0, 1.25, 1.5, 1.75, 2.0]
            let before = steps.filter { inked(along.lowerBound - spacing * $0) }.count
            let after = steps.filter { inked(along.upperBound + spacing * $0) }.count
            return before >= 4 && after >= 4
        }
        columnPeaks.removeAll { passesThrough($0, slope: columnProjection.slope($0), center: centerY, along: yRange, isColumn: true) }
        rowPeaks.removeAll { passesThrough($0, slope: rowProjection.slope($0), center: centerX, along: xRange, isColumn: false) }
        guard max(rowPeaks.count, columnPeaks.count) >= 4, min(rowPeaks.count, columnPeaks.count) >= 2 else { return nil }
        // 书页斜着拍时，横竖两个方向的线距不一样，各算各的；一个方向的线太少、或者算出来差得太多时，用两个方向合起来的。
        // 一个方向只找到两三条线也要（反光挡住了半个图），能认出来的子先摆上，标成没拍全。
        func own(_ peaks: [Double]) -> Double {
            let own = peaks.count >= 4 ? estimateSpacing(peaks, []) : 0
            return abs(own - spacing) <= spacing * 0.2 ? own : spacing
        }
        let rowSpacing = own(rowPeaks), columnSpacing = own(columnPeaks)
        let rows = extend(regularize(rowPeaks, spacing: rowSpacing), to: yRange, spacing: rowSpacing)
        let columns = extend(regularize(columnPeaks, spacing: columnSpacing), to: xRange, spacing: columnSpacing)
        guard max(rows.count, columns.count) >= 5, min(rows.count, columns.count) >= 4 else { return nil }

        // 峰值是拉直后的位置，换回原图上的斜线：v = 位置 + 斜率 × (t - 中心)。
        var horizontalLines = smoothSlopes(rows.map { position in
            let slope = rowProjection.slope(position)
            return fitLine(GridLine(a: position - slope * centerX, b: slope, thickness: 0), pixels: rowPixels, spacing: spacing)
        }, pixels: rowPixels, spacing: spacing)
        var verticalLines = smoothSlopes(columns.map { position in
            let slope = columnProjection.slope(position)
            return fitLine(GridLine(a: position - slope * centerY, b: slope, thickness: 0), pixels: columnPixels, spacing: spacing)
        }, pixels: columnPixels, spacing: spacing)

        addHiddenLines(&horizontalLines, &verticalLines, horizontal: horizontal, vertical: vertical, rowSpacing: rowSpacing, columnSpacing: columnSpacing)

        for i in horizontalLines.indices {
            horizontalLines[i].thickness = thickness(of: horizontalLines[i], along: xRange, spacing: spacing, ink: ink, isHorizontal: true)
        }
        for i in verticalLines.indices {
            verticalLines[i].thickness = thickness(of: verticalLines[i], along: yRange, spacing: spacing, ink: ink, isHorizontal: false)
        }

        // 最外面的线明显比中间的线粗，就是棋盘边。
        let inner = (horizontalLines.dropFirst().dropLast() + verticalLines.dropFirst().dropLast()).map(\.thickness).filter { $0 > 0 }
        let normal = median(inner) ?? 1
        func isEdge(_ line: GridLine) -> Bool { line.thickness >= normal * 1.6 && line.thickness - normal >= 1.5 }
        var edges: DiagramEdges = []
        if isEdge(verticalLines.first!) { edges.insert(.left) }
        if isEdge(verticalLines.last!) { edges.insert(.right) }
        if isEdge(horizontalLines.first!) { edges.insert(.top) }
        if isEdge(horizontalLines.last!) { edges.insert(.bottom) }

        return DetectedGrid(horizontal: horizontalLines, vertical: verticalLines, spacing: spacing, edges: edges)
    }

    /// 靠书缝的那一列挤在阴影里、又被书页弯得变了形，竖线找不到。棋盘线伸过最外面那条线最多半格，
    /// 横线却伸过最后一条竖线快一格了，那里就还有一列，按线距补上。四边都这样看，每边最多补一条。
    static func addHiddenLines(
        _ horizontalLines: inout [GridLine], _ verticalLines: inout [GridLine],
        horizontal: InkMask, vertical: InkMask, rowSpacing: Double, columnSpacing: Double
    ) {
        /// 沿着 lines 里每条线，从和 boundary 的交点往外走，线还连着多远；取中位数。
        func overhang(_ lines: [GridLine], beyond boundary: GridLine, step: Double, mask: InkMask, isHorizontal: Bool, spacing: Double) -> Double {
            var lengths: [Double] = []
            for line in lines {
                // 交点：横线 y = line(x)，竖线 x = boundary(y)，来回代几次。
                var t = 0.0, v = line.value(at: 0)
                for _ in 0..<5 { t = boundary.value(at: v); v = line.value(at: t) }
                var last = 0.0, distance = 1.0, missing = 0.0
                while distance <= spacing * 2 {
                    let pt = t + step * distance, pv = line.value(at: pt)
                    let hit = (-2...2).contains { d in
                        isHorizontal ? mask[Int(pt.rounded()), Int(pv.rounded()) + d] : mask[Int(pv.rounded()) + d, Int(pt.rounded())]
                    }
                    if hit { last = distance; missing = 0 } else { missing += 1 }
                    // 断开超过五分之一格就算到头了（棋子挡住的那几行，取中位数时会被别的行盖过去）。
                    if missing > spacing * 0.2 { break }
                    distance += 1
                }
                lengths.append(last)
            }
            return median(lengths) ?? 0
        }
        func shifted(_ line: GridLine, by offset: Double) -> GridLine {
            var copy = line
            copy.a += offset
            return copy
        }
        guard horizontalLines.count >= 4, verticalLines.count >= 4 else { return }
        if overhang(horizontalLines, beyond: verticalLines.last!, step: 1, mask: horizontal, isHorizontal: true, spacing: columnSpacing) >= columnSpacing * 0.75 {
            verticalLines.append(shifted(verticalLines.last!, by: columnSpacing))
        }
        if overhang(horizontalLines, beyond: verticalLines.first!, step: -1, mask: horizontal, isHorizontal: true, spacing: columnSpacing) >= columnSpacing * 0.75 {
            verticalLines.insert(shifted(verticalLines.first!, by: -columnSpacing), at: 0)
        }
        if overhang(verticalLines, beyond: horizontalLines.last!, step: 1, mask: vertical, isHorizontal: false, spacing: rowSpacing) >= rowSpacing * 0.75 {
            horizontalLines.append(shifted(horizontalLines.last!, by: rowSpacing))
        }
        if overhang(verticalLines, beyond: horizontalLines.first!, step: -1, mask: vertical, isHorizontal: false, spacing: rowSpacing) >= rowSpacing * 0.75 {
            horizontalLines.insert(shifted(horizontalLines.first!, by: -rowSpacing), at: 0)
        }
    }

    /// 平滑后找局部最大值，太弱的不要，挨得太近的只留最强的。
    static func peaks(_ counts: [Double]) -> [Double] {
        guard counts.count > 2 else { return [] }
        let smooth = counts.indices.map { i in
            (max(0, i - 1)...min(counts.count - 1, i + 1)).map { counts[$0] }.reduce(0, +) / 3
        }
        guard let top = smooth.max(), top > 0 else { return [] }
        let threshold = top * 0.3
        var result: [(position: Double, strength: Double)] = []
        for i in smooth.indices where smooth[i] >= threshold {
            let window = max(0, i - 3)...min(smooth.count - 1, i + 3)
            guard window.allSatisfy({ smooth[$0] <= smooth[i] }) else { continue }
            if let last = result.last, Double(i) - last.position < 6 {
                if smooth[i] > last.strength { result[result.count - 1] = (Double(i), smooth[i]) }
            } else {
                result.append((Double(i), smooth[i]))
            }
        }
        return result.map(\.position)
    }

    /// 线距：相邻峰值间隔的中位数，再用接近它的间隔求平均。横竖两个方向一起算。
    static func estimateSpacing(_ rows: [Double], _ columns: [Double]) -> Double {
        let gaps = zip(rows.dropFirst(), rows).map { $0 - $1 } + zip(columns.dropFirst(), columns).map { $0 - $1 }
        guard let rough = median(gaps.filter { $0 >= 6 }) else { return 0 }
        let close = gaps.filter { $0 >= rough * 0.7 && $0 <= rough * 1.3 }
        return close.isEmpty ? rough : close.reduce(0, +) / Double(close.count)
    }

    /// 按线距把峰值排成一列：相邻两个峰之间差不多是几个线距，就等分补上几条线；对不上线距的峰不要。
    /// 等分而不是一个线距一个线距往下推：书页弯曲、斜着拍时线距会慢慢变，推几步就和真的线错开了。
    static func regularize(_ peaks: [Double], spacing: Double) -> [Double] {
        guard var last = peaks.first else { return [] }
        var result = [last]
        for peak in peaks.dropFirst() {
            let gap = peak - last
            let steps = (gap / spacing).rounded()
            guard steps >= 1, abs(gap - steps * spacing) <= spacing * (0.3 + 0.05 * (steps - 1)) else { continue }
            for k in 1...Int(steps) { result.append(last + gap * Double(k) / steps) }
            last = peak
        }
        return result
    }

    /// 外框里两头还放得下线，就按线距补上：那几行（列）被棋子挡满了，没有露出线来。
    /// 压在最外面那条线上的棋子会让外框比线多出约半个线距，所以要再往里留出 0.2 个线距才补。
    static func extend(_ lines: [Double], to range: ClosedRange<Double>, spacing: Double) -> [Double] {
        guard var first = lines.first, var last = lines.last else { return lines }
        var result = lines
        while first - spacing >= range.lowerBound + spacing * 0.2 {
            first -= spacing
            result.insert(first, at: 0)
        }
        while last + spacing <= range.upperBound - spacing * 0.2 {
            last += spacing
            result.append(last)
        }
        return result
    }

    /// 照片拍歪时，直接按行统计会把峰值抹平。书页弯曲、透视还会让同一个图里各条线斜得不一样。
    /// 所以试一遍"基本斜率 + 斜率随位置的变化"，按每组参数把线拉直后统计，峰值最尖（平方和最大）的那组就是。
    /// 返回拉直后的统计，以及每条线的斜率怎么算。
    static func straightenedProjection(
        _ pixels: [(t: Double, v: Double)],
        center: Double,
        range: ClosedRange<Double>
    ) -> (counts: [Double], slope: (Double) -> Double) {
        let length = Int(range.upperBound - range.lowerBound) + 1
        let middle = (range.lowerBound + range.upperBound) / 2
        var best: (counts: [Double], base: Double, change: Double, score: Double) = ([], 0, 0, -1)
        for step in -24...24 {
            let base = Double(step) * 0.005
            for changeStep in -5...5 {
                let change = Double(changeStep) * 0.00003
                var counts = [Double](repeating: 0, count: length)
                for p in pixels {
                    let slope = base + change * (p.v - middle)
                    let index = Int((p.v - slope * (p.t - center) - range.lowerBound).rounded())
                    if counts.indices.contains(index) { counts[index] += 1 }
                }
                let score = counts.reduce(0) { $0 + $1 * $1 }
                if score > best.score { best = (counts, base, change, score) }
            }
        }
        let (base, change) = (best.base, best.change)
        return (best.counts, { position in base + change * (position - middle) })
    }

    /// 一行几乎全是棋子时，线只露出一点点，拟合出来的斜度会被棋子的轮廓带偏。书页上相邻的线斜度差不多，
    /// 和前后两条（中位数）差得多的，按前后的斜度、用自己附近的像素重新定位置。
    static func smoothSlopes(_ lines: [GridLine], pixels: [(t: Double, v: Double)], spacing: Double) -> [GridLine] {
        guard lines.count >= 3 else { return lines }
        let tolerance = 0.015
        return lines.indices.map { index in
            let line = lines[index]
            let neighbors = lines.indices.filter { $0 != index && abs($0 - index) <= 2 }.map { lines[$0] }
            // 斜度按线的中间那一点量（弯的线各处斜度不一样）。
            func slope(_ l: GridLine, at t: Double) -> Double { l.b + 2 * l.c * (t - l.t0) }
            let middle = pixels.isEmpty ? 0 : (pixels.map(\.t).min()! + pixels.map(\.t).max()!) / 2
            guard let typical = median(neighbors.map { slope($0, at: middle) }),
                  abs(slope(line, at: middle) - typical) > tolerance else { return line }
            // 换成前后的斜度，过这条线原来的中点，再用附近的像素挪一挪。
            var fixed = GridLine(a: line.value(at: middle) - typical * middle, b: typical, thickness: 0)
            let near = pixels.filter { abs($0.v - fixed.value(at: $0.t)) <= spacing * 0.2 }
            if near.count >= 10, let shift = median(near.map { $0.v - fixed.value(at: $0.t) }) { fixed.a += shift }
            return fixed
        }
    }

    /// 用估计的线附近的细线像素做最小二乘拟合，去掉离得远的点再拟合一次。像素太少就用估计的线。
    /// 再试一次带弯曲的拟合：线的像素要铺开大半条线，弯得也不能太多（中间和两头差不到半格），不然还用直线。
    private static func fitLine(_ guess: GridLine, pixels: [(t: Double, v: Double)], spacing: Double) -> GridLine {
        let band = spacing * 0.25
        let points = pixels.filter { abs($0.v - guess.value(at: $0.t)) <= band }
        guard points.count >= 20 else { return guess }
        var line = leastSquares(points)
        let kept = points.filter { abs($0.v - line.value(at: $0.t)) <= 2 }
        if kept.count >= 20 { line = leastSquares(kept) }
        // 和估计的斜度差得离谱，说明拟合到了别的东西。
        if abs(line.b - guess.b) > 0.05 { return guess }

        // 线要露出大半条才拟合弯曲：一行几乎全是棋子时，线只露出几小段，硬拟合会弯得乱七八糟。
        guard let first = pixels.map(\.t).min(), let last = pixels.map(\.t).max() else { return line }
        let bins = max(1, Int((last - first) / (spacing / 2)) + 1)
        func coverage(_ points: [(t: Double, v: Double)]) -> Double {
            Double(Set(points.map { Int(($0.t - first) / (spacing / 2)) }).count) / Double(bins)
        }
        var curved = line
        for _ in 0..<2 {
            let near = pixels.filter { abs($0.v - curved.value(at: $0.t)) <= band }
            guard near.count >= 30, coverage(near) >= 0.5, let fit = quadratic(near) else { return line }
            let close = near.filter { abs($0.v - fit.value(at: $0.t)) <= 2 }
            guard close.count >= 30, let refit = quadratic(close) else { return line }
            curved = refit
        }
        let span = (last - first) / 2
        let sag = abs(curved.c) * span * span
        if sag > spacing * 0.5 || abs(curved.b - line.b) > 0.1 { return line }
        return curved
    }

    /// v = a + b·t + c·(t - t0)² 的最小二乘，t0 取这些点的中间，算起来稳。
    private static func quadratic(_ points: [(t: Double, v: Double)]) -> GridLine? {
        let n = Double(points.count)
        let t0 = points.map(\.t).reduce(0, +) / n
        // 用 u = t - t0 拟合 v = p + q·u + c·u²，再换回 a + b·t + c·(t - t0)²：a = p - q·t0，b = q。
        var s = [Double](repeating: 0, count: 5), r = [Double](repeating: 0, count: 3)
        for point in points {
            let u = point.t - t0
            var power = 1.0
            for k in 0..<5 {
                s[k] += power
                if k < 3 { r[k] += power * point.v }
                power *= u
            }
        }
        // 解 3×3 的正规方程 [s0 s1 s2; s1 s2 s3; s2 s3 s4]·[p q c] = r。
        let m = [[s[0], s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]
        func det(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-9 else { return nil }
        func replaced(_ column: Int) -> [[Double]] { m.enumerated().map { i, row in row.enumerated().map { j, v in j == column ? r[i] : v } } }
        let p = det(replaced(0)) / d, q = det(replaced(1)) / d, c = det(replaced(2)) / d
        return GridLine(a: p - q * t0, b: q, thickness: 0, c: c, t0: t0)
    }

    private static func leastSquares(_ points: [(t: Double, v: Double)]) -> GridLine {
        let n = Double(points.count)
        let meanT = points.map(\.t).reduce(0, +) / n
        let meanV = points.map(\.v).reduce(0, +) / n
        var covariance = 0.0, variance = 0.0
        for p in points {
            covariance += (p.t - meanT) * (p.v - meanV)
            variance += (p.t - meanT) * (p.t - meanT)
        }
        let b = variance > 0 ? covariance / variance : 0
        return GridLine(a: meanV - b * meanT, b: b, thickness: 0)
    }

    /// 沿着线量墨迹的宽度，取中位数。碰到棋子（宽度超过线距的四分之一）的地方不算。
    private static func thickness(
        of line: GridLine,
        along range: ClosedRange<Double>,
        spacing: Double,
        ink: InkMask,
        isHorizontal: Bool
    ) -> Double {
        let limit = Int(spacing * 0.3)
        var samples: [Double] = []
        for t in stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: 2) {
            let center = Int(line.value(at: Double(t)).rounded())
            func inked(_ offset: Int) -> Bool { isHorizontal ? ink[t, center + offset] : ink[center + offset, t] }
            // 找线所在的那一段墨迹：中心或旁边一个像素是墨迹。
            guard let start = [0, -1, 1].first(where: inked) else { continue }
            var low = start, high = start
            while low - 1 >= start - limit, inked(low - 1) { low -= 1 }
            while high + 1 <= start + limit, inked(high + 1) { high += 1 }
            let width = high - low + 1
            if Double(width) <= spacing * 0.25 { samples.append(Double(width)) }
        }
        return median(samples) ?? 0
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}
