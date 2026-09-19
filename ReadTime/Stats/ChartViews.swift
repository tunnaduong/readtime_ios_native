import SwiftUI
#if !SKIP
import Charts
#endif

// Swift Charts' Android support via Skip is limited/immature, so both charts used
// by StatsView/TrendsSection are extracted here behind a real-Charts / hand-rolled-bars seam.

#if !SKIP

struct GenreShareBarChart: View {
    let shares: [ReadingStore.GenreShare]

    var body: some View {
        Chart(shares) { share in
            BarMark(
                x: .value("Share", share.percent),
                y: .value("Genre", share.genre)
            )
            .foregroundStyle(Color.readTimePurple.opacity(0.78))
            .cornerRadius(4)
            .annotation(position: .trailing) {
                Text("\(share.percent)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...115)
        .chartXAxis(.hidden)
        .frame(height: CGFloat(shares.count) * 42 + 10)
    }
}

struct TrendBarChart: View {
    let series: [(date: Date, value: Int)]
    let unit: Calendar.Component
    let color: Color

    var body: some View {
        Chart(series, id: \.date) { point in
            BarMark(
                x: .value("Date", point.date, unit: unit),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color.gradient)
            .cornerRadius(3)
        }
        .frame(height: 150)
    }
}

#else

// TODO(android): these hand-rolled bars are plain SwiftUI (no Charts import), so Skip
// transpiles them straight into Compose like any other view — no further interop needed.
// Revisit if closer visual parity with the iOS Swift Charts version is wanted later.

struct GenreShareBarChart: View {
    let shares: [ReadingStore.GenreShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shares) { share in
                HStack(spacing: 8) {
                    Text(share.genre)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.readTimePurple.opacity(0.78))
                            .frame(width: proxy.size.width * CGFloat(share.percent) / 115, height: 22)
                    }
                    .frame(height: 22)
                    Text("\(share.percent)%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: CGFloat(shares.count) * 42 + 10)
    }
}

struct TrendBarChart: View {
    let series: [(date: Date, value: Int)]
    let unit: Calendar.Component
    let color: Color

    var body: some View {
        let maxValue = max(series.map(\.value).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(series, id: \.date) { point in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.gradient)
                    .frame(height: 150 * CGFloat(point.value) / CGFloat(maxValue))
            }
        }
        .frame(height: 150, alignment: .bottom)
    }
}

#endif
