import GoCore
import SwiftUI

/// 作业本：按存进来的日子分组，点一道题放到棋盘上。
struct HomeworkBook: View {
    let homework: HomeworkStore
    let onSelect: (SavedProblem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SavedProblem?

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
                    List {
                        ForEach(days, id: \.day) { group in
                            Section(title(for: group.day)) {
                                ForEach(group.problems) { saved in
                                    Button {
                                        onSelect(saved)
                                    } label: {
                                        HomeworkRow(saved: saved)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button("删除", role: .destructive) { deleting = saved }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("作业本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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

/// 作业本里的一行：小棋盘、题目名和谁先下。
private struct HomeworkRow: View {
    let saved: SavedProblem

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
