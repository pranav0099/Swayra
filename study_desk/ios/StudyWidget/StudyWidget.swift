import WidgetKit
import SwiftUI

// Must match `appGroupId` in lib/models.dart and both targets' App Group capability.
let appGroupId = "group.com.fta.studydesk"

struct StudyEntry: TimelineEntry {
    let date: Date
    let title: String
    let examDate: Date?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry {
        StudyEntry(date: Date(), title: "Exam",
                   examDate: Date().addingTimeInterval(86400 * 30))
    }

    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        let entry = readEntry()
        // Refresh at the next midnight so the day count stays correct.
        let nextMidnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    func readEntry() -> StudyEntry {
        let prefs = UserDefaults(suiteName: appGroupId)
        let title = prefs?.string(forKey: "exam_title") ?? "No exam set"
        var examDate: Date? = nil
        if let ds = prefs?.string(forKey: "exam_date"), !ds.isEmpty {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            examDate = fmt.date(from: ds)
        }
        return StudyEntry(date: Date(), title: title, examDate: examDate)
    }
}

struct StudyWidgetEntryView: View {
    var entry: Provider.Entry

    var daysLeft: Int? {
        guard let exam = entry.examDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: exam)).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT UP")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
            if let days = daysLeft {
                Text("\(days)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("days left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Set a date").font(.headline)
            }
            Spacer()
            Text(entry.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

@main
struct StudyWidget: Widget {
    let kind: String = "StudyWidget" // must match iOSWidget in lib/models.dart

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                StudyWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StudyWidgetEntryView(entry: entry).padding()
            }
        }
        .configurationDisplayName("Exam Countdown")
        .description("Days left until your exam.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
