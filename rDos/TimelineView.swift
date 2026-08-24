import SwiftUI
import SwiftData

/// 时间线主页：按天倒序的一切记录。
struct TimelineView: View {
    let records: [Record]
    let actions: RecordActions
    var contentTopInset: CGFloat
    var selectedTag: String? = nil

    private struct DaySection: Identifiable {
        let day: Date
        let records: [Record]
        var id: Date { day }
    }

    private var visibleRecords: [Record] {
        guard let selectedTag else { return records }
        return records.filter { $0.tags.contains(selectedTag) }
    }

    private var sections: [DaySection] {
        let groups = Dictionary(grouping: visibleRecords) { DayPlanner.normalizedDay($0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            DaySection(day: day, records: (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if sections.isEmpty {
                    EmptyStateView(
                        icon: selectedTag == nil ? "square.and.pencil" : "number",
                        title: selectedTag == nil ? "还没有记录" : "“#\(selectedTag!)” 下还没有记录",
                        subtitle: selectedTag == nil
                            ? "在下方输入栏随手记一条：想法、待办、照片或语音"
                            : "给记录加上 #\(selectedTag!) 标签就会出现在这里"
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
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayTitle(section.day))
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.secondaryText)
                .padding(.leading, 2)
            ForEach(Array(section.records.enumerated()), id: \.element.persistentModelID) { position, record in
                RecordRowView(record: record, actions: actions)
                    .reportFrame(position == 0 && section.day == sections.first?.day ? "firstRecord" : nil)
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

/// 分类页：#标签聚合 + 各标签下最新一条预览。
struct TagsView: View {
    let records: [Record]
    var onPickTag: (String) -> Void

    private struct TagGroup: Identifiable {
        let tag: String
        let count: Int
        let latest: Record?
        var id: String { tag }
    }

    private var groups: [TagGroup] {
        var dict: [String: [Record]] = [:]
        for record in records {
            for tag in record.tags {
                dict[tag, default: []].append(record)
            }
        }
        return dict
            .map { tag, list in
                let sorted = list.sorted { $0.createdAt > $1.createdAt }
                return TagGroup(tag: tag, count: list.count, latest: sorted.first)
            }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if groups.isEmpty {
                    EmptyStateView(
                        icon: "number",
                        title: "还没有标签",
                        subtitle: "记录里写上 #想法 #成长 之类的标签\n就能在这里聚合查看"
                    )
                } else {
                    ForEach(groups) { group in
                        tagCard(group)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    private func tagCard(_ group: TagGroup) -> some View {
        Button {
            onPickTag(group.tag)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(group.tag)")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text("\(group.count) 条")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText.opacity(0.7))
                }
                if let latest = group.latest {
                    HStack(spacing: 8) {
                        kindIcon(latest)
                        Text(latest.text.isEmpty ? kindLabel(latest) : latest.text)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(DayPlanner.hm(latest.createdAt))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.secondaryText.opacity(0.8))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.cardTint)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private func kindIcon(_ record: Record) -> some View {
        Image(systemName: iconSystemName(record))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
    }

    private func iconSystemName(_ record: Record) -> String {
        switch record.kind {
        case .text: return "text.quote"
        case .todo: return record.isDone ? "checkmark.circle.fill" : "circle"
        case .photo: return "photo"
        case .voice: return "waveform"
        }
    }

    private func kindLabel(_ record: Record) -> String {
        switch record.kind {
        case .text: return "文字记录"
        case .todo: return "待办"
        case .photo: return "照片"
        case .voice: return "语音"
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
