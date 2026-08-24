import SwiftUI
import SwiftData

/// 时间线主页：按天倒序的一切记录。
struct TimelineView: View {
    let records: [Record]
    let actions: RecordActions
    var contentTopInset: CGFloat

    private struct DaySection: Identifiable {
        let day: Date
        let records: [Record]
        var id: Date { day }
    }

    private var sections: [DaySection] {
        let unpinned = records.filter { !$0.isPinned }
        let groups = Dictionary(grouping: unpinned) { DayPlanner.normalizedDay($0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            DaySection(day: day, records: (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    private var pinnedRecords: [Record] {
        records.filter(\.isPinned).sorted { $0.createdAt > $1.createdAt }
    }

    @State private var lastFirstRecordID: PersistentIdentifier?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Color.clear.frame(height: 0).id("timeline-top")
                if !pinnedRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("置顶")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.secondaryText)
                            .padding(.leading, 2)
                        ForEach(pinnedRecords) { record in
                            RecordRowView(record: record, actions: actions)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.badgeBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if sections.isEmpty && pinnedRecords.isEmpty {
                    EmptyStateView(
                        icon: "square.and.pencil",
                        title: "还没有记录",
                        subtitle: "在下方输入栏随手记一条：想法、待办、照片或语音"
                    )
                } else {
                    ForEach(sections) { section in
                        daySection(section)
                    }
                }
            }
                .padding(.top, contentTopInset + 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onChange(of: records.first?.persistentModelID) { _, _ in
            // 新记录插入到顶部（且是更新的一条）时，滚动定位最新一条
            let newFirst = records.first
            let isNewer: Bool
            if let newFirst, let lastID = lastFirstRecordID,
               let oldFirst = records.first(where: { $0.persistentModelID == lastID }) {
                isNewer = newFirst.createdAt > oldFirst.createdAt
            } else if newFirst != nil, lastFirstRecordID == nil {
                isNewer = false
            } else {
                isNewer = newFirst != nil && lastFirstRecordID != nil
            }
            defer { lastFirstRecordID = newFirst?.persistentModelID }
            guard isNewer else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo("timeline-top", anchor: .top)
            }
        }
        .onAppear {
            lastFirstRecordID = records.first?.persistentModelID
        }
        }
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle(section.day))
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.secondaryText)
                .padding(.leading, 2)
            ForEach(section.records) { record in
                RecordRowView(record: record, actions: actions)
            }
        }
        .clipped()
    }

    private func dayTitle(_ day: Date) -> String {
        let index = DayPlanner.dayIndex(of: day, hour: 4, minute: 0)
        let dateText = DayPlanner.localizedDate(day)
        switch index {
        case 0: return "今天 · \(dateText)"
        case 1: return "昨天 · \(dateText)"
        default: return dateText
        }
    }
}


struct EmptyStateView: View {
    var icon: String = "tray"
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.secondaryText.opacity(0.6))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}
