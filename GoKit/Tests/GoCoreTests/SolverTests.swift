import Foundation
import Testing
@testable import GoCore

@Suite("判题")
struct SolverTests {
    /// 白子只剩一口气，旁边有白棋接应：黑棋要马上提，不然白棋接上就逃了。
    private let captureProblem = Problem(
        setup: Board(diagram: """
            . . . . . . . . .
            . . . . . . . . .
            . . . . . . . . .
            . . . . X . . . .
            . . . X O X . . .
            . . . . . . . . .
            . . . . O . . . .
            . . . . O . . . .
            . . . . . . . . .
            """),
        toPlay: .black,
        goal: .capture
    )

    @Test("吃子题：找出要吃的白子")
    func infersCaptureTarget() throws {
        let objective = try #require(Objective.infer(for: captureProblem))
        #expect(objective.attacker == .black)
        #expect(objective.targets == [Point(4, 4)])
    }

    @Test("吃子题：提子就答对，不提就被白棋接走")
    func judgesCapture() throws {
        let solver = try #require(ProblemSolver(problem: captureProblem))
        let start = captureProblem.startPosition
        #expect(solver.judge(try start.playing(Point(4, 5)).position) == .solved)
        #expect(solver.judge(try start.playing(Point(0, 0)).position) == .wrong)
        #expect(solver.correctMoves(in: start) == [Point(4, 5)])
    }

    @Test("下错时，对方应在破解的那一手")
    func repliesWithRefutation() throws {
        let solver = try #require(ProblemSolver(problem: captureProblem))
        let afterWrong = try captureProblem.startPosition.playing(Point(0, 0)).position
        #expect(solver.reply(in: afterWrong) == Point(4, 5))
    }

    @Test("逃子题：长出去连上自己的棋")
    func judgesEscape() throws {
        let problem = Problem(
            setup: Board(diagram: """
                . . . . . . . . .
                . . . . . . . . .
                . . . . . . . . .
                . . . . O . . . .
                . . . O X O . . .
                . . . . . . . . .
                . . . . X . . . .
                . . . . X . . . .
                . . . . . . . . .
                """),
            toPlay: .black,
            goal: .escape
        )
        let solver = try #require(ProblemSolver(problem: problem))
        #expect(solver.objective.attacker == .white)
        let start = problem.startPosition
        #expect(solver.judge(try start.playing(Point(4, 5)).position) == .solved)
        #expect(solver.judge(try start.playing(Point(0, 0)).position) == .wrong)
    }

    @Test("征子：一路打吃到边上")
    func ladder() throws {
        let problem = Problem(
            setup: Board(diagram: """
                . . . . . . . . .
                . . . . . . . . .
                . . . X . . . . .
                . . X O . . . . .
                . . . . X . . . .
                . . . . . . . . .
                . . . . . . . . .
                . . . . . . . . .
                . . . . . . . . .
                """),
            toPlay: .black,
            goal: .capture
        )
        let solver = try #require(ProblemSolver(problem: problem))
        let start = problem.startPosition
        #expect(solver.judge(try start.playing(Point(4, 3)).position) == .correct)
    }

    @Test("不支持的题型不判")
    func unsupportedGoal() {
        var problem = captureProblem
        problem.goal = .live
        #expect(ProblemSolver(problem: problem) == nil)
        problem.goal = nil
        #expect(ProblemSolver(problem: problem) == nil)
    }

    @Test("第 7 题：找出对杀的两块棋")
    func sampleObjective() throws {
        let objective = try #require(Objective.infer(for: .sample))
        // 白棋中间三子是要吃的，黑棋被紧气的两子是要保的。
        #expect(objective.targets == [Point(2, 16)])
        #expect(objective.guards == [Point(5, 16)])
    }

    /// 正解是 E2：黑棋长在公气上，自己变 3 口气、白棋变 2 口气，快一气。
    @Test("第 7 题：正解是 E2，其他紧气的下法都不对")
    func sampleSolution() throws {
        let solver = try #require(ProblemSolver(problem: .sample))
        let start = Problem.sample.startPosition
        let e2 = Point(4, 17)
        #expect(solver.correctMoves(in: start) == [e2])
        #expect(solver.judge(try start.playing(e2).position) == .correct)
        for wrong in [Point(2, 17), Point(3, 17), Point(5, 18)] {
            #expect(solver.judge(try start.playing(wrong).position) == .wrong, "\(Coordinates.name(of: wrong, size: 19))")
        }
    }

    @Test("第 7 题：下对以后接着下，能把白棋三子吃掉")
    func samplePlayThrough() throws {
        let solver = try #require(ProblemSolver(problem: .sample))
        var position = try Problem.sample.startPosition.playing(Point(4, 17)).position
        // 白棋应一手，黑棋再下正解，直到吃掉为止。
        for _ in 0..<6 {
            if let reply = solver.reply(in: position) {
                position = try position.playing(reply).position
            } else {
                position = position.passing()
            }
            let move = try #require(solver.correctMoves(in: position).first)
            position = try position.playing(move).position
            if solver.judge(position) == .solved { break }
        }
        #expect(solver.judge(position) == .solved)
        #expect(position.board[Point(3, 16)] == nil)
    }
}
