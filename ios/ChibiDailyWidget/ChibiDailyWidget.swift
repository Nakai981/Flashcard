import WidgetKit
import SwiftUI

struct DailyWordEntry: TimelineEntry {
    let date: Date
    let word: String
    let phonetic: String
    let meaning: String
    let summary: String
}

struct DailyWordProvider: TimelineProvider {
    private let appGroupId = "group.com.chibi.flashcard"

    private func loadEntry() -> DailyWordEntry {
        var word = "Serendipity"
        var phonetic = "ˌserənˈdipədē"
        var meaning = "Sự tình cờ may mắn"
        var summary = "💎 Từ mới Chibi trong ngày"

        // 1. Đọc từ App Group UserDefaults (nếu tài khoản Apple Developer có bật App Groups)
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            if let w = groupDefaults.string(forKey: "chibi_widget_word"), !w.isEmpty {
                word = w
                phonetic = groupDefaults.string(forKey: "chibi_widget_phonetic") ?? ""
                meaning = groupDefaults.string(forKey: "chibi_widget_meaning") ?? ""
                summary = groupDefaults.string(forKey: "chibi_widget_summary") ?? summary
                return DailyWordEntry(
                    date: Date(),
                    word: word,
                    phonetic: phonetic,
                    meaning: meaning,
                    summary: summary
                )
            }
        }

        // 2. Đọc từ App Group Container JSON file (nếu có)
        if let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let fileUrl = containerUrl.appendingPathComponent("chibi_daily_widget.json")
            if let data = try? Data(contentsOf: fileUrl),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                word = json["word"] ?? word
                phonetic = json["phonetic"] ?? phonetic
                meaning = json["meaning"] ?? meaning
                summary = json["summary"] ?? summary
            }
        }

        return DailyWordEntry(
            date: Date(),
            word: word,
            phonetic: phonetic,
            meaning: meaning,
            summary: summary
        )
    }

    func placeholder(in context: Context) -> DailyWordEntry {
        DailyWordEntry(
            date: Date(),
            word: "Serendipity",
            phonetic: "ˌserənˈdipədē",
            meaning: "Sự tình cờ may mắn",
            summary: "💎 Từ mới Chibi trong ngày"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyWordEntry) -> ()) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWordEntry>) -> ()) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct ChibiDailyWordWidgetEntryView: View {
    var entry: DailyWordProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // Tiện ích Màn hình khóa iOS (Khung chữ nhật dưới đồng hồ Lock Screen)
            VStack(alignment: .leading, spacing: 2) {
                Text("💎 \(entry.word)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                if !entry.phonetic.isEmpty {
                    Text("/\(entry.phonetic)/")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .italic()
                        .lineLimit(1)
                }
                Text(entry.meaning)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .accessoryInline:
            // Tiện ích Màn hình khóa iOS (Dòng chữ ngay phía trên đồng hồ Lock Screen)
            Text("💎 \(entry.word): \(entry.meaning)")

        case .accessoryCircular:
            // Tiện ích Màn hình khóa iOS (Ô tròn trên Lock Screen)
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Text("💎")
                        .font(.system(size: 12))
                    Text(entry.word)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            }

        default:
            // Tiện ích Màn hình chính (Home Screen Small / Medium) tông Xanh Dương iPhone 15 Plus
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.summary)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.17, green: 0.45, blue: 0.84))
                    .lineLimit(1)

                Text(entry.word)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.29))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !entry.phonetic.isEmpty {
                    Text("/\(entry.phonetic)/")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .italic()
                        .foregroundColor(Color(red: 0.36, green: 0.46, blue: 0.59))
                        .lineLimit(1)
                }

                Text(entry.meaning)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.17, green: 0.45, blue: 0.84))
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.95, green: 0.97, blue: 0.99))
        }
    }
}

@main
struct ChibiDailyWordWidget: Widget {
    let kind: String = "ChibiDailyWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyWordProvider()) { entry in
            if #available(iOS 17.0, *) {
                ChibiDailyWordWidgetEntryView(entry: entry)
                    .containerBackground(Color(red: 0.95, green: 0.97, blue: 0.99), for: .widget)
            } else {
                ChibiDailyWordWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Từ Mới Chibi Trong Ngày")
        .description("Hiển thị từ vựng mới của Flashcard ngay trên Màn hình khóa và Màn hình chính.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular,
            .systemSmall,
            .systemMedium
        ])
    }
}
