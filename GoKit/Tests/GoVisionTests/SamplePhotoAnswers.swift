import Foundation
import GoCore
import Testing
@testable import GoVision

/// 2026-10-24 拍的 9 张作业照片（第 34～43 页），每道题照着书逐点抄下来的答案。
/// 照片不进仓库；本机有照片时，拿识别结果逐点对答案，算认错了几个点（需求说明 F2.7）。
let samplePhotoAnswers: [(photo: String, page: Int?, diagrams: [(number: Int?, rows: [String])])] = [
    // 第 34 页：拍的时候手晃了，竖线糊成浅灰色；右边一列挨着书缝的阴影
    ("IMG_0353.HEIC", 34, [
        (1, [
            ".........",
            ".........",
            ".........",
            "...O.....",
            ".........",
            "..OOXX...",
            ".O.XOOXX.",
            ".....OOX.",
            ".........",
        ]),
        (2, [
            ".........",
            ".........",
            ".........",
            "..O......",
            "...O.....",
            "..XOX....",
            "..OX.X...",
            ".OOX.....",
            ".OXX.....",
        ]),
        (3, [
            ".........",
            ".........",
            ".........",
            ".........",
            "....X....",
            "..X.XOO..",
            "XXXOOX.O.",
            "OOXO.....",
            "OOOO.....",
        ]),
        (4, [
            ".........",
            ".........",
            ".........",
            "..X......",
            ".X....O..",
            "OOOOX....",
            "XXXXOO...",
            ".X.XO....",
            ".XOO.....",
        ]),
        (5, [
            ".........",
            ".........",
            ".........",
            ".........",
            "....X....",
            "..X.XOO..",
            "..XOOX.O.",
            "..X......",
            ".........",
        ]),
        (6, [
            ".........",
            ".........",
            ".........",
            "..X......",
            "..XOOX.O.",
            "...OXXO..",
            "..XXOO...",
            ".........",
            ".........",
        ]),
    ]),
    // 第 35 页：10 题只读出 "0"，7～9 题读不出题号
    ("IMG_0354.HEIC", 35, [
        (7, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".....X...",
            "..XXXOO..",
            ".XOOOXO..",
            ".....XO..",
            ".........",
        ]),
        (8, [
            ".........",
            ".........",
            ".........",
            ".........",
            "..O......",
            "..OXXX...",
            ".OXOOOXX.",
            ".OX...OX.",
            ".........",
        ]),
        (9, [
            ".........",
            ".........",
            ".........",
            "..O......",
            "..OXX....",
            ".OXO.....",
            ".OXO.X...",
            ".OX......",
            ".........",
        ]),
        (10, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            ".OOOXX...",
            "..XXOX...",
            "...OOX...",
            ".........",
        ]),
        (11, [
            ".........",
            ".........",
            ".........",
            ".O.O.....",
            "..OXX....",
            ".OXOX.X..",
            ".OXOOOX..",
            "OXX...X..",
            ".........",
        ]),
        (12, [
            ".........",
            ".........",
            "..OOOO...",
            "..OXX.O..",
            "..XO.....",
            "..XO..O..",
            "..XO.....",
            "...XX....",
            ".........",
        ]),
    ]),
    // 第 36 页：竖线有点糊；17 题底下有铅笔印；15、17 题只读出 "5"、"7"
    ("IMG_0355.HEIC", 36, [
        (13, [
            ".........",
            ".........",
            ".........",
            ".O.......",
            "...O..X..",
            ".O.OXX...",
            ".OXXOOXX.",
            "OXXOO....",
            ".........",
        ]),
        (14, [
            ".........",
            ".........",
            ".........",
            "..X......",
            "....O....",
            ".XXXO.O..",
            ".XOOXXO.O",
            "...OOXXO.",
            ".........",
        ]),
        (15, [
            ".........",
            ".........",
            ".........",
            ".........",
            "....O....",
            "..O.OXXX.",
            ".OXXXOOX.",
            ".O.XOO.OX",
            ".........",
        ]),
        (16, [
            ".........",
            "..O......",
            ".........",
            "..XX.....",
            "..OXO....",
            ".OOXO....",
            ".OXO.O...",
            ".XXO.....",
            ".........",
        ]),
        (17, [
            ".........",
            ".........",
            ".........",
            ".........",
            "...O.....",
            ".O.OXXX..",
            ".OXXOOX.X",
            "..XOO.OX.",
            ".....XO..",
        ]),
        (18, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".O.O..X..",
            ".O.OXX...",
            ".OXXOOXX.",
            "OXXOO.O..",
            "...X.....",
        ]),
    ]),
    // 第 37 页：19～23 题上有铅笔印、橡皮屑
    ("IMG_0356.HEIC", 37, [
        (19, [
            ".........",
            ".........",
            ".........",
            ".........",
            "....O....",
            "....OXXX.",
            "OOOOXOOX.",
            "OXOXXXO..",
            "X.XX.XO..",
        ]),
        (20, [
            ".........",
            ".........",
            ".........",
            ".OO......",
            "OXO......",
            ".XO......",
            "XOOXXXX..",
            "XXXOOOX..",
            ".XOO.....",
        ]),
        (21, [
            ".........",
            ".........",
            ".........",
            "OOO......",
            "XXO......",
            ".XO....X.",
            "XOOXXXX..",
            "XXXOOOOX.",
            "..XO.....",
        ]),
        (22, [
            ".........",
            ".OO......",
            "OOXOO....",
            "XXXXO....",
            ".XXOO....",
            "XOOOXX...",
            "XXXXOX.X.",
            ".XOOOOX..",
            ".XO......",
        ]),
        (23, [
            ".........",
            ".........",
            ".........",
            ".XXX.....",
            ".XOOO....",
            "XOXXOO...",
            ".OX.XOOOO",
            ".OX.XOXXO",
            ".OXX.XXOO",
        ]),
        (24, [
            "OO.......",
            "X.O......",
            ".XO......",
            "XOO......",
            "XXO.X.X..",
            ".XOXXOXX.",
            "XOOXOXOX.",
            "XXXOO.OX.",
            ".XOO.OOX.",
        ]),
    ]),
    // 第 39 页：讲解页，灰底的图，没有题号
    ("IMG_0357.HEIC", 39, [
        (nil, [
            "........",
            "........",
            "........",
            "........",
            ".......O",
            "..XXXXXO",
            ".XOOOOXO",
            ".X..X.O.",
        ]),
        (nil, [
            "........",
            "........",
            "........",
            "........",
            ".......O",
            "..XXXXXO",
            ".XOOOOXO",
            ".XX.XOO.",
        ]),
        (nil, [
            "........",
            "........",
            "........",
            "........",
            ".......O",
            "..XXXXXO",
            ".XOOOOXO",
            ".X..XXO.",
        ]),
        (nil, [
            "........",
            "........",
            "........",
            "........",
            ".......O",
            "..XXXXXO",
            ".XOOOOXO",
            ".X.O.XO.",
        ]),
    ]),
    // 第 40 页：右边一列挨着书缝，书页卷起来了
    ("IMG_0358.HEIC", 40, [
        (1, [
            ".........",
            ".........",
            ".........",
            ".........",
            "......O..",
            "..XXXXO..",
            "..XOOXO..",
            ".XOO.O...",
            ".XX......",
        ]),
        (2, [
            ".........",
            ".........",
            ".........",
            ".XX......",
            ".OOXXX...",
            ".OXOOX.X.",
            ".OX..OX..",
            ".OX.O.OX.",
            ".........",
        ]),
        (3, [
            ".........",
            ".........",
            ".XXXX....",
            ".....X...",
            ".O.OX....",
            ".XOOX....",
            ".XXXO....",
            ".OOOO....",
            ".........",
        ]),
        (4, [
            ".........",
            ".........",
            ".........",
            "....X....",
            ".........",
            "..XXXOO..",
            ".OXOOXO..",
            "..O.OX.O.",
            ".....X...",
        ]),
        (5, [
            ".........",
            ".........",
            "....X....",
            "..XX.....",
            "..O......",
            "..OXXXOO.",
            ".XXOXOXO.",
            ".OOOXOX.O",
            "....OO...",
        ]),
        (6, [
            ".........",
            ".........",
            ".........",
            "..O......",
            "..OXXXX..",
            ".OXOOOOX.",
            ".OXO...X.",
            ".OXXOXX..",
            "....OX...",
        ]),
    ]),
    // 第 41 页：横着拍的
    ("IMG_0359.HEIC", 41, [
        (7, [
            ".........",
            ".........",
            ".........",
            "XXX......",
            ".OX......",
            "O.OX.....",
            "O.OX.....",
            "XOOX.X...",
            ".OXX.....",
        ]),
        (8, [
            ".........",
            ".........",
            ".........",
            "..XXXX...",
            "..XOOOX..",
            "...O.OX..",
            ".XXOOXX..",
            ".XO..OX..",
            ".X.OOOX..",
        ]),
        (9, [
            ".........",
            ".........",
            ".........",
            ".........",
            "XXXX.....",
            "XOOX.....",
            ".OXX.XX.X",
            "O.OOOOOX.",
            "O.O.X....",
        ]),
        (10, [
            ".........",
            ".........",
            "..X......",
            "...XX....",
            "..XOOX...",
            "..XO..X..",
            "XXXOXX...",
            "OOO.OX...",
            "....OX...",
        ]),
        (11, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".X.......",
            "..XXX....",
            "OX..OXX..",
            ".OOO.OX..",
            "O..O.OX..",
        ]),
        (12, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            "X.XXXX.X.",
            "OX.OO.X..",
            "OOO..O.X.",
            ".XXOOXX..",
        ]),
    ]),
    // 第 42 页：横着拍的，右边一列挨着书缝，书页卷得厉害；隔壁页露出半截图
    ("IMG_0360.HEIC", 42, [
        (13, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".OOO.....",
            "OXX......",
            ".OX.X....",
            "XOX......",
            ".OX......",
        ]),
        (14, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            "......XX.",
            "XXXXXXOX.",
            "OOOOOXOX.",
            ".O.X.OO..",
        ]),
        (15, [
            ".........",
            ".........",
            "...O.O...",
            "....O....",
            "..XXOXX..",
            "..XO.OX..",
            "..XOXOX..",
            "..XO.OX..",
            "..XOOOX..",
        ]),
        (16, [
            ".........",
            ".........",
            ".........",
            "XXX......",
            "OOX......",
            ".OX......",
            "OOX.X....",
            ".OXOX....",
            "X.OOX....",
        ]),
        (17, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            ".......O.",
            "..XXXXXO.",
            ".XOOOOXO.",
            ".X..X.O..",
        ]),
        (18, [
            ".........",
            ".........",
            ".........",
            ".........",
            ".........",
            "......OO.",
            "XXXXXXXO.",
            ".OXOOOO..",
            "OOO.X....",
        ]),
    ]),
    // 第 43 页：照片底下没拍到页码；19、21、22 题只读出 "1"、"2"、"2"
    ("IMG_0361.HEIC", nil, [
        (19, [
            ".........",
            "..O......",
            "..OXX....",
            ".O.OX....",
            ".XO....X.",
            ".XXOOOX..",
            ".XOXXX...",
            ".OO......",
            ".........",
        ]),
        (20, [
            ".........",
            ".........",
            ".........",
            ".........",
            "...XXXO..",
            ".X.XOOXO.",
            "..XO..XO.",
            ".XO.O.XO.",
            ".........",
        ]),
        (21, [
            ".........",
            "..O......",
            ".........",
            "O.O......",
            "XO..X....",
            "XXOOX....",
            ".XXOX.O..",
            ".X.XOO...",
            "..X......",
        ]),
        (22, [
            ".........",
            ".........",
            ".O.......",
            "..OO.....",
            "XXXO.....",
            "XOOX.....",
            ".OXX.X...",
            "O.O......",
            "O.O......",
        ]),
        (23, [
            ".........",
            ".........",
            ".O.......",
            "..O......",
            ".OXX.....",
            "OXOXXX...",
            "OXOOXOO..",
            ".XO.OXO..",
            ".X.......",
        ]),
        (24, [
            ".........",
            ".........",
            "....O.O..",
            ".........",
            "...XO....",
            "..XO..X..",
            "..XOOOX..",
            "...XXX...",
            ".........",
        ]),
    ]),
]

private let answerFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("棋盘照片样例")

private func answerPhoto(_ name: String) -> URL? {
    let url = answerFolder.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

/// 每张照片只认一次，两个测试共用。和 App 导入时一样，先按文字方向转正。
private let recognizedAnswers: [String: RecognizedPage] = {
    var pages: [String: RecognizedPage] = [:]
    for answer in samplePhotoAnswers {
        guard let url = answerPhoto(answer.photo), let image = PhotoLoader.image(at: url),
              let page = try? PageRecognizer.recognize(PageOrientation.upright(image)) else { continue }
        pages[answer.photo] = page
    }
    return pages
}()

extension PhotoSuites {
@Suite("对答案", .enabled(if: samplePhotoAnswers.allSatisfy { answerPhoto($0.photo) != nil }, "本机没有这 9 张样例照片"))
struct SampleAnswerTests {
    @Test("9 张照片 52 道题都找到，题号、页码都对：手晃糊了的、挨着书缝的、灰底的图都算")
    func pages() throws {
        for answer in samplePhotoAnswers {
            let page = try #require(recognizedAnswers[answer.photo])
            #expect(page.pageNumber == answer.page, "\(answer.photo) 的页码")
            #expect(page.diagrams.map(\.number) == answer.diagrams.map(\.number), "\(answer.photo) 的题号")
        }
    }

    @Test("逐点对答案：认错的点不到棋子数的 2%；铅笔印不当黑子，书缝的阴影不当一列棋子")
    func stones() throws {
        var points = 0, stones = 0, wrong = 0
        for answer in samplePhotoAnswers {
            let page = try #require(recognizedAnswers[answer.photo])
            for (index, expected) in answer.diagrams.enumerated() {
                points += expected.rows.count * expected.rows[0].count
                stones += expected.rows.joined().filter { $0 != "." }.count
                // 有题号按题号对，讲解页没有题号，按顺序对。
                let found = expected.number.map { number in page.diagrams.first { $0.number == number } } ?? page.diagrams[safe: index]
                let rows = found.map { $0.stones.map { row in String(row.map { $0 == .black ? "X" : $0 == .white ? "O" : "." }) } } ?? []
                for (row, line) in expected.rows.enumerated() {
                    for (column, want) in line.enumerated() {
                        let got = rows[safe: row].flatMap { Array($0)[safe: column] } ?? "?"
                        guard got != want else { continue }
                        wrong += 1
                        print("\(answer.photo) 第 \(expected.number.map(String.init) ?? "\(index + 1)") 题 第 \(row + 1) 行第 \(column + 1) 列：认成 \(got)，应该是 \(want)")
                    }
                }
            }
        }
        print("对答案：\(points) 个点、\(stones) 颗子，认错 \(wrong) 个点")
        #expect(points == 4144 && stones == 1060)
        // 需求文档的指标是“单颗棋子误判率不超过 2%”：认错的点（多认、漏认、认反颜色）按棋子数算。
        #expect(wrong * 50 <= stones, "认错的点不能超过棋子数的 2%")
        // 现在错 8 个，都在挨着书缝的右边一列题里。多出来说明改坏了。
        #expect(wrong <= 8)
    }
}
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
