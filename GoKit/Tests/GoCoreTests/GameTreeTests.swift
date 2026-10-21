import Testing
@testable import GoCore

@Suite("变化树")
struct GameTreeTests {
    private func emptyTree() -> GameTree {
        GameTree(root: Position(board: Board(size: 9)))
    }

    @Test("落子、悔棋、重做")
    func playUndoRedo() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        try tree.play(Point(3, 3))
        #expect(tree.lastMove == Point(3, 3))
        #expect(tree.position.toPlay == .black)

        tree.undo()
        #expect(tree.lastMove == Point(2, 2))
        #expect(tree.position.board[Point(3, 3)] == nil)
        tree.redo()
        #expect(tree.lastMove == Point(3, 3))
        #expect(!tree.canRedo)
    }

    @Test("悔棋后换一种下法，原来的变化还在，重做走最近的那个")
    func branches() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        let first = tree.currentID
        tree.undo()
        try tree.play(Point(6, 6))
        let second = tree.currentID

        #expect(tree[GameTree.rootID].children == [first, second])
        tree.undo()
        tree.redo()
        #expect(tree.currentID == second)
    }

    @Test("再下同一手时走进原来的变化，不重复建")
    func reusesExistingChild() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        let first = tree.currentID
        tree.undo()
        try tree.play(Point(2, 2))
        #expect(tree.currentID == first)
        #expect(tree[GameTree.rootID].children.count == 1)
    }

    @Test("不合法的一手不进树")
    func illegalMoveIsRejected() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        #expect(throws: MoveError.occupied) { try tree.play(Point(2, 2)) }
        #expect(tree[GameTree.rootID].children.count == 1)
    }

    @Test("删除当前变化，退回到上一手")
    func deleteVariation() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        let first = tree.currentID
        tree.undo()
        try tree.play(Point(6, 6))
        try tree.play(Point(5, 5))
        let branch = tree[tree.currentID].parent!

        tree.deleteVariation(branch)
        #expect(tree.currentID == GameTree.rootID)
        #expect(tree[GameTree.rootID].children == [first])
        tree.redo()
        #expect(tree.currentID == first)
    }

    @Test("跳到别的变化，重做跟着走")
    func goToNode() throws {
        var tree = emptyTree()
        try tree.play(Point(2, 2))
        try tree.play(Point(3, 3))
        let deep = tree.currentID
        tree.goToRoot()
        try tree.play(Point(6, 6))
        tree.go(to: deep)
        #expect(tree.path.count == 3)
        tree.goToRoot()
        tree.redo()
        tree.redo()
        #expect(tree.currentID == deep)
    }

    @Test("停一手")
    func pass() throws {
        var tree = emptyTree()
        tree.pass()
        #expect(tree.current.move == .pass)
        #expect(tree.lastMove == nil)
        #expect(tree.position.toPlay == .white)
        #expect(tree.mover(of: tree.currentID) == .black)
    }
}
