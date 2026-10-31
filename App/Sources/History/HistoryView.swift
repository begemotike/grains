import GrainsCore
import SwiftUI

/// The History window content: week navigation, entries by day (newest first), inline edit,
/// soft delete with Undo, and restore of entries deleted in this session.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
            List {
                if model.entries.isEmpty {
                    Text("No entries this week.").foregroundStyle(.secondary)
                }
                ForEach(model.days, id: \.day) { group in
                    Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(group.entries) { entry in
                            HistoryRow(entry: entry, model: model, isEditing: editingID == entry.id) { editing in
                                editingID = editing ? entry.id : nil
                            }
                        }
                    }
                }
                if !model.recentlyDeleted.isEmpty {
                    Section("Deleted in this session") {
                        ForEach(model.recentlyDeleted) { entry in
                            HStack {
                                Text(entry.rawText).strikethrough().foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore") { model.restore(entry) }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { model.reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { model.previousWeek() } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
            Button { model.nextWeek() } label: { Image(systemName: "chevron.right") }
                .disabled(model.isCurrentWeek)
                .help("Next week")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.week.isoIdentifier).font(.headline.monospacedDigit())
                Text(model.week.interval.start.formatted(.dateTime.month().day()) + " – " +
                     model.week.interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Formatting.hours(model.weekHours)) h")
                .font(.system(.title3, design: .monospaced).monospacedDigit())
            if !model.isCurrentWeek {
                Button("This Week") { model.currentWeek() }
            }
            if !model.recentlyDeleted.isEmpty {
                Button("Undo Delete") { model.undoDelete() }
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(12)
    }
}

/// One entry: time range, duration and raw text, with an inline editor.
struct HistoryRow: View {
    let entry: Entry
    let model: HistoryModel
    let isEditing: Bool
    let setEditing: (Bool) -> Void

    @State private var start = Date()
    @State private var stop = Date()
    @State private var text = ""

    var body: some View {
        if isEditing { editor } else { summary }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(range)
                .font(.system(.body, design: .monospaced).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(Formatting.clock(seconds: Int(entry.duration(asOf: Date()))))
                .font(.system(.body, design: .monospaced).monospacedDigit())
                .frame(width: 80, alignment: .leading)
            Text(entry.rawText)
                .lineLimit(1)
                .truncationMode(.tail)
            if entry.metadata.recovered.map({ !$0.reconciled }) == true {
                Text("recovered").font(.caption).foregroundStyle(Theme.error)
            }
            if model.overlaps(entry) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.error).help("Overlaps another entry")
            }
            Spacer()
            Button { beginEditing() } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Edit")
            Button { model.delete(entry) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Client - note", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                if entry.isRunning {
                    Text("running").foregroundStyle(Theme.accent)
                } else {
                    DatePicker("Stop", selection: $stop, displayedComponents: [.date, .hourAndMinute])
                }
                Spacer()
                Button("Cancel") { setEditing(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let newText: String? = text == entry.rawText ? nil : text
                    if model.save(entry, start: start, stop: entry.isRunning ? nil : stop, newText: newText) {
                        setEditing(false)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 4)
    }

    private func beginEditing() {
        start = entry.startedAt
        stop = entry.stoppedAt ?? Date()
        text = entry.rawText
        setEditing(true)
    }

    private var range: String {
        let s = Formatting.time(entry.startedAt)
        guard let stop = entry.stoppedAt else { return "\(s) – now" }
        return "\(s) – \(Formatting.time(stop))"
    }
}
