import GoCore
import SwiftUI

/// 摆题和做题的主界面。iPad 横屏时棋盘在左、操作面板在右；竖屏时面板在棋盘下面。
public struct ProblemEditorView: View {
    @Bindable private var model: ProblemEditorModel
    /// 家长选的思考深度，下次打开 App 还是这个。
    @AppStorage("engineDepth") private var storedDepth: EngineDepth = .standard
    /// 家长选的对弈棋力，下次打开 App 还是这一档。
    @AppStorage("aiStrength") private var storedStrength: AIStrength = .beginner

    public init(model: ProblemEditorModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height

            // 做题时只显示局部棋谱（比如 9×7 路），比整盘窄很多；横屏下如果棋盘还占满整列宽度，
            // 为了保持格子是正方形，上下就会留出很宽的空白。这里按可用高度反推棋盘实际需要的宽度，
            // 省下来的宽度让给右边面板，棋盘就能顶天立地，不再因为局部棋谱的形状而上下留白。
            let availableWidth = proxy.size.width - 48
            let availableHeight = proxy.size.height - 48
            let boardAspect = BoardGeometry.aspectRatio(region: model.region, showCoordinates: model.showCoordinates)
            let minPanelWidth: CGFloat = 320
            let maxPanelWidth: CGFloat = 460
            let boardWidth: CGFloat? = wide
                ? max(200, min(availableHeight * boardAspect, availableWidth - minPanelWidth - 24))
                : nil
            let panelWidth: CGFloat? = wide
                ? max(minPanelWidth, min(maxPanelWidth, availableWidth - (boardWidth ?? 0) - 24))
                : nil

            let layout = wide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 16))
            layout {
                BoardView(
                    board: model.displayedBoard,
                    region: model.region,
                    labels: model.displayedLabels,
                    lastMove: model.lastMove,
                    ghost: model.ghost,
                    highlighted: model.mode == .setup ? model.stonesWithoutLiberties : [],
                    uncertain: model.mode == .setup ? model.uncertainPoints : [],
                    territory: model.territory,
                    showCoordinates: model.showCoordinates,
                    onTap: model.tap
                )
                .frame(width: boardWidth)
                .frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)

                ScrollView {
                    panel
                }
                .frame(width: panelWidth)
                .frame(maxHeight: wide ? .infinity : proxy.size.height * 0.4)
            }
            .padding(24)
        }
        .background(Theme.background)
        .onChange(of: storedDepth, initial: true) { model.engineDepth = storedDepth }
        .onChange(of: storedStrength, initial: true) { model.aiStrength = storedStrength }
        .confirmationDialog("重新开始一盘？现在这盘就没了", isPresented: $model.isConfirmingNewGame, titleVisibility: .visible) {
            Button("新的一盘", role: .destructive) { model.newGame() }
        }
        .confirmationDialog(
            "换成 \(model.pendingGameSize ?? 9) 路会重新开始一盘，现在这盘就没了",
            isPresented: Binding(
                get: { model.pendingGameSize != nil },
                set: { if !$0 { model.pendingGameSize = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("换成 \(model.pendingGameSize ?? 9) 路", role: .destructive) {
                if let size = model.pendingGameSize { model.changeGameSize(to: size) }
            }
        }
        .confirmationDialog(
            "换棋盘大小会清空已摆的棋子",
            isPresented: Binding(
                get: { model.pendingBoardSize != nil },
                set: { if !$0 { model.pendingBoardSize = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("清空并换成 \(model.pendingBoardSize ?? 19) 路", role: .destructive) {
                if let size = model.pendingBoardSize { model.changeBoardSize(to: size) }
            }
        }
        .confirmationDialog("清空棋盘上所有棋子？", isPresented: $model.isConfirmingClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { model.clearBoard() }
        }
        .sheet(isPresented: $model.isChoosingDiagram) {
            DiagramChooser(model: model)
        }
        .sheet(isPresented: $model.isShowingHomework) {
            if let homework = model.homework {
                HomeworkBook(homework: homework, onSelect: model.load)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModeSwitcherBar(mode: model.mode) { model.switchMode(to: $0) }

            // 放在面板最上面：竖屏时面板要滚动，放在下面孩子看不到。
            if model.isThinking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("想一想……").font(.title3).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let message = model.message {
                MessageBanner(message: message)
            }

            switch model.mode {
            case .setup: setupControls
            case .solve: solveControls
            case .play: gameControls
            }

            Divider()
            Toggle("显示坐标", isOn: $model.showCoordinates)
        }
        .padding(4)
    }

    // MARK: - 摆题

    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            ImportControls(model: model)

            TextField("题目名称，比如第 35 页第 7 题", text: $model.problem.title)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SetupTool.allCases) { tool in
                    ToolButton(title: tool.name, selected: model.tool == tool) {
                        model.select(tool)
                    } icon: {
                        ToolIcon(tool: tool)
                    }
                }
            }

            if let reference = model.referenceImage {
                ReferenceImage(image: reference, hasUncertain: !model.uncertainPoints.isEmpty)
            }
            if model.problem.region != nil {
                Toggle("显示全盘", isOn: $model.showWholeBoard)
            }

            LabeledContent("谁先下") {
                Picker("谁先下", selection: $model.problem.toPlay) {
                    Text("黑先").tag(Stone.black)
                    Text("白先").tag(Stone.white)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }

            LabeledContent("题目类型") {
                Picker("题目类型", selection: $model.problem.goal) {
                    ForEach(ProblemGoal.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
            }
            Text(model.problem.goal.explanation(player: model.problem.toPlay))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.judgeSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("棋盘") {
                Picker("棋盘", selection: boardSizeBinding) {
                    ForEach(Board.supportedSizes, id: \.self) { Text("\($0) 路").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            Text("黑子 \(model.problem.setup.count(of: .black)) 个 · 白子 \(model.problem.setup.count(of: .white)) 个")
                .foregroundStyle(.secondary)

            if !model.stonesWithoutLiberties.isEmpty {
                Label("红圈里的棋子没有气，请检查", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                model.isConfirmingClear = true
            } label: {
                Label("清空棋盘", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private var boardSizeBinding: Binding<Int> {
        Binding(get: { model.problem.setup.size }, set: { model.requestBoardSize($0) })
    }

    // MARK: - 做题

    private var solveControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.problem.title.isEmpty {
                Text(model.problem.title).font(.headline)
            }

            HStack(spacing: 12) {
                StoneIcon(stone: model.position.toPlay, size: 36)
                Text("轮到\(model.position.toPlay.name)棋下")
                    .font(.title2.weight(.bold))
            }

            Text("\(model.problem.toPlay.name)先")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    model.undo()
                } label: {
                    Label("悔棋", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canUndo)

                Button {
                    model.redo()
                } label: {
                    Label("重做", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canRedo)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.restart()
            } label: {
                Label("重新开始", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !model.variationChoices.isEmpty {
                variationControls
            }

            Text("黑提 \(model.position.blackCaptures) 子 · 白提 \(model.position.whiteCaptures) 子")
                .foregroundStyle(.secondary)

            if model.canJudge {
                engineControls
            } else if !model.hasEngine {
                Text(model.judgeSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            confirmControls
            Toggle("显示全盘", isOn: $model.showWholeBoard)
        }
    }

    // MARK: - 对弈

    private var gameControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StoneIcon(stone: model.position.toPlay, size: 36)
                Text("轮到\(model.position.toPlay.name)棋下")
                    .font(.title2.weight(.bold))
            }
            if model.canJudge && model.autoReply {
                Text("你执\(model.humanColor.name) · AI 执\(model.humanColor.opponent.name)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    model.undo()
                } label: {
                    Label("悔棋", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canUndo)

                Button {
                    model.redo()
                } label: {
                    Label("重做", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canRedo)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.endAndCount()
            } label: {
                Label("结束，数子", systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isThinking)

            if !model.variationChoices.isEmpty {
                variationControls
            }

            Text("黑提 \(model.position.blackCaptures) 子 · 白提 \(model.position.whiteCaptures) 子")
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("棋盘") {
                Picker("棋盘", selection: Binding(get: { model.gameSize }, set: { model.requestGameSize($0) })) {
                    ForEach(Board.supportedSizes, id: \.self) { Text("\($0) 路").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            LabeledContent("我执") {
                Picker("我执", selection: $model.humanColor) {
                    Text("黑").tag(Stone.black)
                    Text("白").tag(Stone.white)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            Button {
                model.requestNewGame()
            } label: {
                Label("新的一盘", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isThinking)

            if model.canJudge {
                engineControls
            } else {
                Text("没有引擎，不能打分，AI 也不能陪下，只能两个人轮流下")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            confirmControls
        }
    }

    // MARK: - 共用

    /// 打分、陪下的开关和思考深度；对弈时还有 AI 棋力。
    @ViewBuilder
    private var engineControls: some View {
        let game = model.mode == .play
        Toggle("AI 打分", isOn: $model.autoScore)
        Text(model.autoScore
            ? "每一手显示比最好的下法亏几目"
            : "不显示分数，随时可以再打开")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Toggle("AI 陪下", isOn: $model.autoReply)
        Text(model.autoReply ? "AI 替对手下" : (game ? "两个人轮流下" : "自己两边下"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        if game && model.autoReply {
            Picker("AI 棋力", selection: $storedStrength) {
                ForEach(AIStrength.allCases, id: \.self) { strength in
                    Text(strength.name).tag(strength)
                }
            }
            .pickerStyle(.segmented)
            Text(storedStrength.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if model.autoScore || model.autoReply {
            Picker("思考深度", selection: $storedDepth) {
                ForEach(EngineDepth.allCases, id: \.self) { depth in
                    Text(depth.name).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            // 对弈时和棋力放在一起，说清楚深度管的是打分，不是 AI 让多少。
            Text(game ? "思考深度：打分算得多仔细，越深越准、等得越久。\(storedDepth.detail)" : "思考深度：\(storedDepth.detail)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var confirmControls: some View {
        Toggle("落子前确认", isOn: $model.confirmMoves)
        if model.confirmMoves {
            Text("点一下看位置，再点一次才落子")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension ProblemEditorView {
    /// 同一步试过几种下法时，可以来回切换；字母和棋盘上标的一致。
    private var variationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这一步试过的下法").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], alignment: .leading, spacing: 8) {
                ForEach(model.variationChoices) { choice in
                    Button {
                        model.selectVariation(choice.id)
                    } label: {
                        Text(choice.label)
                            .fontWeight(choice.isCurrent ? .bold : .regular)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(choice.isCurrent ? Color.accentColor : Color.gray)
                    .accessibilityAddTraits(choice.isCurrent ? .isSelected : [])
                }
            }
            Button(role: .destructive) {
                model.deleteCurrentVariation()
            } label: {
                Label("删掉现在这个变化", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

#if os(iOS)
#Preview("iPad 横屏", traits: .landscapeLeft) {
    ProblemEditorView(model: ProblemEditorModel())
}
#endif
