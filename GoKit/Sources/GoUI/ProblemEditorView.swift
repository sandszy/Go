import GoCore
import SwiftUI

/// 摆题和做题的主界面。iPad 横屏时棋盘在左、操作面板在右；竖屏时面板在棋盘下面。
public struct ProblemEditorView: View {
    @Bindable private var model: ProblemEditorModel
    /// 家长选的思考深度，下次打开 App 还是这个。
    @AppStorage("engineDepth") private var storedDepth: EngineDepth = .standard

    public init(model: ProblemEditorModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
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
                    showCoordinates: model.showCoordinates,
                    onTap: model.tap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    panel
                }
                .frame(width: wide ? 320 : nil)
                .frame(maxHeight: wide ? .infinity : proxy.size.height * 0.4)
            }
            .padding(24)
        }
        .background(Theme.background)
        .onChange(of: storedDepth, initial: true) { model.engineDepth = storedDepth }
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
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("模式", selection: Binding(get: { model.mode }, set: { model.switchMode(to: $0) })) {
                ForEach(EditorMode.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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

            LabeledContent("题目目标") {
                Picker("题目目标", selection: $model.problem.goal) {
                    Text("未设置").tag(ProblemGoal?.none)
                    ForEach(ProblemGoal.allCases) { Text($0.name).tag(Optional($0)) }
                }
                .labelsHidden()
            }
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

            if let goal = model.problem.goal {
                Text("\(model.problem.toPlay.name)先 · \(goal.name)")
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
                Toggle("AI 陪下", isOn: $model.autoJudge)
                Text(model.autoJudge
                    ? "AI 判每一手的对错，并替\(model.problem.toPlay.opponent.name)棋应"
                    : "自己两边下，随时可以再打开")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if model.autoJudge && model.hasEngine {
                    Picker("思考深度", selection: $storedDepth) {
                        ForEach(EngineDepth.allCases, id: \.self) { depth in
                            Text(depth.name).tag(depth)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("思考深度：\(storedDepth.detail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("落子前确认", isOn: $model.confirmMoves)
            if model.confirmMoves {
                Text("点一下看位置，再点一次才落子")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("显示全盘", isOn: $model.showWholeBoard)
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
