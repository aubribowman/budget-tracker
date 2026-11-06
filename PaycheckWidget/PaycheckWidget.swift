import WidgetKit
import SwiftUI

/// What the app shares with the widget. The app writes this to the shared App Group
/// folder every time your budget changes (see WidgetSync.swift in the app).
struct WidgetSummary: Codable {
    var updated: Date
    var left: Double              // left on the current paycheck
    var paycheckDate: Date?       // payday of the current paycheck
    var nextPayday: Date?
    var billsDue: Int
    var billsDueAmount: Double
    var pastDue: Int
    var spendingLeft: Double
    var spendingBudget: Double
    var goalName: String?
    var goalSaved: Double
    var goalTarget: Double

    /// The App Group shared with the app: "group." plus the app's ID, which is the
    /// widget's ID without ".PaycheckWidget" on the end.
    static let groupId: String = {
        let id = Bundle.main.bundleIdentifier ?? "com.aubribowman.PaycheckApp.PaycheckWidget"
        return "group." + id.split(separator: ".").dropLast().joined(separator: ".")
    }()
    static let fileName = "widget.json"

    static func load() -> WidgetSummary? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId),
              let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSummary.self, from: data)
    }

    static let sample = WidgetSummary(updated: .now, left: 612.40, paycheckDate: .now, nextPayday: Calendar.current.date(byAdding: .day, value: 6, to: .now),
                                      billsDue: 2, billsDueAmount: 385, pastDue: 0, spendingLeft: 157.45, spendingBudget: 415,
                                      goalName: "Emergency fund", goalSaved: 1950, goalTarget: 5000)
}

struct Entry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, summary: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, summary: context.isPreview ? .sample : (WidgetSummary.load() ?? .sample)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app asks for a refresh whenever your budget changes. Refresh after
        // midnight too, so "in 3 days" counts down.
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))) ?? .now
        completion(Timeline(entries: [Entry(date: .now, summary: WidgetSummary.load())], policy: .after(next)))
    }
}

// MARK: - Look

private let green = Color(red: 10 / 255, green: 51 / 255, blue: 35 / 255)
private let moss = Color(red: 131 / 255, green: 153 / 255, blue: 88 / 255)
private let rosy = Color(red: 211 / 255, green: 150 / 255, blue: 140 / 255)

private func money(_ v: Double, cents: Bool = true) -> String {
    v.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
}

private func daysAway(_ d: Date?) -> String {
    guard let d else { return "" }
    let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: d)).day ?? 0
    return n <= 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days"
}

struct PaycheckWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        if let s = entry.summary {
            switch family {
            case .accessoryRectangular: lockRect(s)
            case .accessoryCircular: lockCircle(s)
            case .accessoryInline: Text("\(money(s.left, cents: false)) left · payday \(daysAway(s.nextPayday))")
            case .systemMedium: medium(s)
            default: small(s)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "banknote").foregroundStyle(moss)
                Text("Open Paycheck Plan to set up your widget.").font(.caption)
            }
        }
    }

    func small(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Left on paycheck").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(money(s.left)).font(.title2.weight(.heavy)).minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(s.left < 0 ? rosy : .primary)
            Spacer(minLength: 0)
            if s.pastDue > 0 {
                Label("\(s.pastDue) past due", systemImage: "exclamationmark.circle.fill").font(.caption2.weight(.semibold)).foregroundStyle(rosy)
            } else if s.billsDue > 0 {
                Text("\(s.billsDue) \(s.billsDue == 1 ? "bill" : "bills"), \(money(s.billsDueAmount, cents: false)) due").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("All caught up").font(.caption2).foregroundStyle(moss)
            }
            if s.nextPayday != nil {
                Label("Payday \(daysAway(s.nextPayday))", systemImage: "calendar").font(.caption2.weight(.semibold)).foregroundStyle(moss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func medium(_ s: WidgetSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(s)
            VStack(alignment: .leading, spacing: 8) {
                bar("Spending left", money(s.spendingLeft, cents: false),
                    s.spendingBudget > 0 ? 1 - s.spendingLeft / s.spendingBudget : 0, s.spendingLeft < 0 ? rosy : moss)
                if let g = s.goalName {
                    bar(g, "\(money(s.goalSaved, cents: false)) of \(money(s.goalTarget, cents: false))",
                        s.goalTarget > 0 ? s.goalSaved / s.goalTarget : 0, green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func bar(_ label: String, _ value: String, _ p: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value: max(0, min(1, p))).tint(c)
        }
    }

    func lockRect(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(money(s.left)) left").font(.headline).widgetAccentable()
            Text(s.pastDue > 0 ? "\(s.pastDue) past due" : s.billsDue > 0 ? "\(s.billsDue) \(s.billsDue == 1 ? "bill" : "bills") due" : "All caught up").font(.caption)
            Text("Payday \(daysAway(s.nextPayday))").font(.caption)
        }
    }

    func lockCircle(_ s: WidgetSummary) -> some View {
        Gauge(value: max(0, min(1, s.spendingBudget > 0 ? s.spendingLeft / s.spendingBudget : 0))) {
            Image(systemName: "cart")
        } currentValueLabel: {
            Text(money(s.spendingLeft, cents: false)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct PaycheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PaycheckWidget", provider: Provider()) { entry in
            PaycheckWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Paycheck")
        .description("What's left on this paycheck, bills due, and your next payday.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct PaycheckWidgetBundle: WidgetBundle {
    var body: some Widget { PaycheckWidget() }
}
