import GoCore
import SwiftUI

/// 作业本：按存进来的日子分组，点一道题放到棋盘上。点“选择”可以选好几道、全选，一起删；例题删不掉。
struct HomeworkBook: View {
    let homework: HomeworkStore
    let onSelect: (SavedProblem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SavedProblem?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var isConfirmingBatch = false

    var body: some View {
        NavigationStack {
            Group {
                if homework.problems.isEmpty {
                    ContentUnavailableView(
                        "作业本还是空的",
                        systemImage: "books.vertical",
                        description: Text("拍过的题会自动存在这里，手动摆的题点“保存这道题”")
                    )
                } else {
                    // 不在选择的时候不给 List 选中的绑定，点一行就是打开这道题。
                    List(selection: isSelecting ? $selection : .constant([])) {
                        ForEach(days, id: \.day) { group in
                            Section(title(for: group.day)) {
                                ForEach(group.problems) { saved in
                                    row(saved)
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
                    #endif
                    .safeAreaInset(edge: .bottom) {
                        if isSelecting {
                            Button(role: .destructive) {
                                isConfirmingBatch = true
                            } label: {
                                Text("删除 \(selection.count) 道题").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                            .disabled(selection.isEmpty)
                            .padding()
                            .background(.bar)
                        }
                    }
                }
            }
            .navigationTitle("作业本")
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        let all = homework.deletableIDs
                        Button(!all.isEmpty && selection == all ? "全不选" : "全选") {
                            selection = selection == all ? [] : all
                        }
                        .disabled(all.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { stopSelecting() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("选择") { isSelecting = true }
                            .disabled(homework.deletableIDs.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                "从作业本里删掉选中的 \(selection.count) 道题？删了就找不回来了",
                isPresented: $isConfirmingBatch,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    homework.delete(selection)
                    stopSelecting()
                }
            }
            .confirmationDialog(
                "从作业本里删掉\(deleting.map { name(of: $0.problem) } ?? "")？删了就找不回来了",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let deleting { homework.delete(deleting.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ saved: SavedProblem) -> some View {
        if isSelecting {
            // 选择的时候点一行只是选中，不打开题；例题那行不能选。
            HomeworkRow(saved: saved, showsExampleNote: true)
                .tag(saved.id)
                .selectionDisabled(saved.isExample)
        } else {
            Button {
                onSelect(saved)
            } label: {
                HomeworkRow(saved: saved, showsExampleNote: false)
            }
            .buttonStyle(.plain)
            .swipeActions {
                if !saved.isExample {
                    Button("删除", role: .destructive) { deleting = saved }
                }
            }
        }
    }

    private func stopSelecting() {
        isSelecting = false
        selection = []
    }

    private var days: [(day: Date, problems: [SavedProblem])] {
        let calendar = Calendar.current
        var groups: [(day: Date, problems: [SavedProblem])] = []
        for saved in homework.problems {
            let day = calendar.startOfDay(for: saved.saved)
            if groups.last?.day == day {
                groups[groups.count - 1].problems.append(saved)
            } else {
                groups.append((day, [saved]))
            }
        }
        return groups
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let date = "\(parts.month ?? 0) 月 \(parts.day ?? 0) 日"
        return calendar.isDate(day, equalTo: .now, toGranularity: .year) ? date : "\(parts.year ?? 0) 年 \(date)"
    }
}

/// 作业本里的一行：小棋盘、题目名和谁先下。选择的时候例题那行写着不能删。
private struct HomeworkRow: View {
    let saved: SavedProblem
    let showsExampleNote: Bool

    var body: some View {
        let problem = saved.problem
        HStack(spacing: 16) {
            BoardView(board: problem.setup, region: problem.region ?? .fitting(problem.setup), labels: problem.labels)
                .frame(width: 88, height: 88)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                Text(name(of: problem)).font(.headline)
                Text("\(problem.toPlay.name)先")
                    .foregroundStyle(.secondary)
                if saved.isIncomplete {
                    Text("没拍全").font(.footnote).foregroundStyle(.orange)
                }
                if showsExampleNote && saved.isExample {
                    Text("例题不能删").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private func name(of problem: Problem) -> String {
    problem.title.isEmpty ? "没起名的题" : problem.title
}
