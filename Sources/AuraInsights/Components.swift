import AuraKit
import Charts
import SwiftUI

/// Big number tile with an optional trend versus the previous period.
struct KPITile: View {
    let title: String
    let value: String
    var symbol: String = "clock"
    var tint: Color = .accentColor
    var trend: Double? = nil
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsIcon(symbol, color: tint, size: 20)
                Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let trend, trend.isFinite {
                    Text("\(trend >= 0 ? "▲" : "▼") \(abs(Int((trend * 100).rounded()))) %")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(trend >= 0 ? .green : .orange)
                        .help("Par rapport à la période précédente")
                }
            }
            Text(value)
                .font(.system(.title, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentSurface(cornerRadius: 12, padding: 14)
    }
}

/// Titled container for a chart or list, styled like a grouped form section.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) { content }
                .contentSurface(cornerRadius: 12, padding: 14)
        }
    }
}

/// Ranked list with artwork, bar and time.
struct RankingList: View {
    let items: [RankedItem]
    var tint: Color = .accentColor
    var showCount: String? = nil
    var empty = "Pas encore de données"

    var body: some View {
        if items.isEmpty {
            Text(empty).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
        } else {
            let maxSeconds = items.map(\.seconds).max() ?? 1
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                        Artwork(url: item.image, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label).font(.callout.weight(.medium)).lineLimit(1)
                            if let sub = item.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(tint.gradient)
                                        .frame(width: max(4, geo.size.width * item.seconds / max(maxSeconds, 1)))
                                }
                                .frame(height: 4)
                            }
                            .frame(height: 4)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.duration(item.seconds)).font(.callout.monospacedDigit())
                            if let showCount { Text("\(item.count) \(showCount)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

struct Artwork: View {
    let url: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(.quaternary)
            .overlay(Image(systemName: "sparkles").font(.system(size: size * 0.35)).foregroundStyle(.secondary))
    }
}

/// Stacked daily (or hourly) bars.
struct TimeSeriesChart: View {
    let buckets: [TimeBucket]
    let byHour: Bool
    var colorFor: (String) -> Color = Kind.color
    var labelFor: (String) -> String = Kind.title

    var body: some View {
        let groups = Array(Set(buckets.map(\.group))).sorted()
        Chart(buckets) { b in
            BarMark(
                x: .value("Date", b.date, unit: byHour ? .hour : .day),
                y: .value("Heures", b.seconds.hoursValue)
            )
            .foregroundStyle(by: .value("Type", labelFor(b.group)))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: groups.map(labelFor), range: groups.map(colorFor))
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Double.self) { Text("\(h, format: .number.precision(.fractionLength(0...1))) h") } } } }
        .frame(height: 220)
    }
}

/// Weekday × hour heat map.
struct HeatmapChart: View {
    let cells: [HeatCell]
    var tint: Color = .accentColor
    private let days = ["", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    var body: some View {
        let maxValue = max(cells.map(\.seconds).max() ?? 1, 1)
        Chart(cells) { c in
            RectangleMark(
                x: .value("Heure", c.hour),
                y: .value("Jour", days[c.weekday]),
                width: .ratio(0.92), height: .ratio(0.85)
            )
            .foregroundStyle(tint.opacity(c.seconds == 0 ? 0.06 : 0.15 + 0.85 * c.seconds / maxValue))
            .cornerRadius(3)
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { v in AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } } } }
        .chartYScale(domain: Array(days.dropFirst()))
        .frame(height: 210)
    }
}

/// Distribution donut.
struct DonutChart: View {
    let items: [(label: String, seconds: TimeInterval, color: Color)]

    var body: some View {
        let total = items.reduce(0) { $0 + $1.seconds }
        HStack(spacing: 18) {
            Chart(items, id: \.label) { item in
                SectorMark(angle: .value("Temps", item.seconds), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
            }
            .frame(width: 150, height: 150)
            .overlay {
                VStack(spacing: 0) {
                    Text(Format.hours(total)).font(.title3.weight(.semibold).monospacedDigit())
                    Text("au total").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 8) {
                        Circle().fill(item.color).frame(width: 9, height: 9)
                        Text(item.label).font(.callout)
                        Spacer()
                        Text(total > 0 ? "\(Int((item.seconds / total * 100).rounded())) %" : "–").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Text(Format.duration(item.seconds)).font(.callout.monospacedDigit()).frame(minWidth: 80, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Hour-of-day profile (0–23).
struct HourProfileChart: View {
    let buckets: [TimeBucket]
    var tint: Color = .accentColor

    var body: some View {
        Chart(Array(buckets.enumerated()), id: \.offset) { index, b in
            AreaMark(x: .value("Heure", index), y: .value("Heures", b.seconds.hoursValue))
                .foregroundStyle(tint.opacity(0.25).gradient)
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Heure", index), y: .value("Heures", b.seconds.hoursValue))
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: 0...23)
        .chartXAxis { AxisMarks(values: [0, 4, 8, 12, 16, 20]) { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } } } }
        .chartYAxis(.hidden)
        .frame(height: 150)
    }
}

func trend(_ now: TimeInterval, _ before: TimeInterval) -> Double? {
    before > 60 ? (now - before) / before : nil
}

func timeString(_ c: DateComponents?) -> String {
    guard let c, let h = c.hour, let m = c.minute else { return "–" }
    return String(format: "%02d:%02d", h, m)
}
