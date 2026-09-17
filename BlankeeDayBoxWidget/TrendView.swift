//
//  TrendView.swift
//  BlankeeDayBoxWidget
//
//  The balance trend graphs from dashboard_summary, one at a time in a medium
//  widget: the checking balance, then each credit account, then savings. The
//  two arrows in the header step through them and wrap at both ends, so a tap
//  past savings comes back round to checking.
//
//  Drawn the way the page draws them: a two-point line with a faint fill under
//  it, teal for the budget and savings, grey for a card, a month per point and
//  today's point filled orange with "Today" over it.
//

import Charts
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct TrendEntry: TimelineEntry {
    enum State {
        case loaded(Trends)
        case message(title: String, detail: String?)
    }

    let date: Date
    /// Which series is showing, already wrapped into range by the provider.
    let page: Int
    let state: State
}

// MARK: - Provider

struct TrendProvider: TimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> TrendEntry {
        TrendEntry(date: Date(), page: 0, state: .loaded(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping (TrendEntry) -> Void) {
        if context.isPreview || !WidgetStore.isConfigured {
            completion(TrendEntry(date: Date(), page: 0, state: .loaded(.placeholder)))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: entry))))
        }
    }

    private func load() async -> TrendEntry {
        var page = WidgetStore.listPage(for: kind)
        do {
            let trends = try await TrendService.fetch()

            // The arrows only move the stored number; how many series there are
            // is known here and nowhere else. Wrapping rather than clamping is
            // what makes "next" from the last one land on the first, and the
            // wrapped value is written back so the count of taps stays small.
            let count = max(1, trends.series.count)
            let wrapped = ((page % count) + count) % count
            if wrapped != page {
                WidgetStore.setListPage(wrapped, for: kind)
                page = wrapped
            }
            return TrendEntry(date: Date(), page: page, state: .loaded(trends))
        } catch let error as DayBoxError {
            let (title, detail) = error.widgetMessage
            return TrendEntry(date: Date(), page: page, state: .message(title: title, detail: detail))
        } catch {
            return TrendEntry(date: Date(), page: page, state: .message(title: "Can't reach Blankee", detail: nil))
        }
    }

    /// The same schedule as the day widgets: quarter-hourly while it has data,
    /// half-hourly while it is showing a message, and always by midnight so
    /// the month holding today moves on when the date does.
    private static func nextRefresh(after entry: TrendEntry) -> Date {
        let interval: TimeInterval
        switch entry.state {
        case .message: interval = 30 * 60
        case .loaded:  interval = 15 * 60
        }
        let regular = Date().addingTimeInterval(interval)
        guard let midnight = Calendar.current.nextDate(after: Date(),
                                                       matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                       matchingPolicy: .nextTime) else {
            return regular
        }
        return min(regular, midnight)
    }
}

extension DayBoxError {
    /// The title and detail a widget shows for each failure. Shared by every
    /// provider so "signed out" reads the same on all of them.
    var widgetMessage: (String, String?) {
        switch self {
        case .notConfigured:
            return ("Blankee", "Open the app and sign in to set up this widget.")
        case .serverTooOld:
            return ("Server needs updating", "This Blankee server doesn't have widget support yet.")
        case .unauthorized:
            return ("Signed out", "Open Blankee to sign in again.")
        case .server, .transport, .badResponse:
            return ("Can't reach Blankee", errorDescription)
        }
    }
}

// MARK: - View

struct TrendView: View {
    let entry: TrendEntry
    let kind: String

    private enum T {
        static let headerHeight: CGFloat = 26
        static let corner: CGFloat = 8
        static let inset: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Link(destination: blankeeSummaryDeepLink) {
                content
            }
        }
        .background(Color.blankeeWhite)
        .clipShape(RoundedRectangle(cornerRadius: T.corner, style: .continuous))
    }

    // MARK: Header

    private var current: TrendSeries? {
        guard case .loaded(let trends) = entry.state, !trends.series.isEmpty else { return nil }
        return trends.series[min(entry.page, trends.series.count - 1)]
    }

    private var header: some View {
        ZStack {
            if let series = current {
                HStack(spacing: 5) {
                    Text(icon(for: series.kind))
                        .font(BlankeeFont.awesome(11))
                    Text(series.name)
                        .font(BlankeeFont.bold(13))
                        .lineLimit(1)
                    trendArrow(series)
                }
                .foregroundStyle(color(for: series.kind))
                .padding(.horizontal, 60)
            } else {
                Text("Balance Trend")
                    .font(BlankeeFont.bold(13))
                    .foregroundStyle(Color.blankeePrimary)
            }

            HStack(spacing: 0) {
                pageButton(FAIcon.circleLeft, delta: -1, label: "Previous graph")
                Spacer(minLength: 0)
                pageButton(FAIcon.circleRight, delta: 1, label: "Next graph")
            }
            .padding(.horizontal, 5)
        }
        .frame(height: T.headerHeight)
        .frame(maxWidth: .infinity)
    }

    private func pageButton(_ icon: String, delta: Int, label: String) -> some View {
        Button(intent: ShiftPageIntent(kind: kind, delta: delta)) {
            Text(icon)
                .font(BlankeeFont.awesome(15))
                .foregroundStyle(Color.blankeePrimary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The page's arrow beside the title: where the line ends against where it
    /// is today. Up and down carry the page's meaning - a rising balance is
    /// good, a rising card balance is not - so the colour follows the series,
    /// not the direction.
    @ViewBuilder
    private func trendArrow(_ series: TrendSeries) -> some View {
        let window = series.window()
        if let todayIndex = window.todayIndex, let last = window.points.last,
           window.points.count >= 2 {
            let today = window.points[todayIndex].value
            Text(last.value > today ? FAIcon.arrowTrendUp
                 : last.value < today ? FAIcon.arrowTrendDown : FAIcon.minus)
                .font(BlankeeFont.awesome(10))
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .loaded(let trends):
            if let series = current {
                let window = series.window()
                if window.points.isEmpty {
                    empty("No \(series.name.lowercased()) data yet")
                } else {
                    chart(window, series: series, symbol: trends.currencySymbol)
                }
            } else {
                empty("Nothing to graph yet")
            }
        case .message(let title, let detail):
            MessageCard(title: title, detail: detail)
                .padding(T.inset)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(BlankeeFont.regular(11))
            .foregroundStyle(Color.blankeeSecondaryDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chart(_ window: TrendSeries.Window, series: TrendSeries, symbol: String) -> some View {
        let color = color(for: series.kind)
        let points = window.points
        // The forecast can run for years, so the axis names only as many months
        // as fit - about seven "Sep '26" labels across a medium widget - and the
        // dots between them are left to speak for themselves.
        let labelStep = max(1, Int((Double(points.count) / 7).rounded(.up)))
        let dense = points.count > 16
        // The low point of the stretch shown, called out the way the summary
        // page's buffer card calls out the lowest the balance is projected to
        // reach: the one number that says whether the months ahead are safe.
        // The first of equal lows wins, so it is the soonest.
        let lowIndex = points.indices.min { points[$0].value < points[$1].value }

        return Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                AreaMark(x: .value("Month", index), y: .value("Balance", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.opacity(0.1))

                LineMark(x: .value("Month", index), y: .value("Balance", point.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(color)

                PointMark(x: .value("Month", index), y: .value("Balance", point.value))
                    .symbol {
                        let isToday = index == window.todayIndex
                        let isLow = index == lowIndex
                        let size: CGFloat = (isToday || isLow) ? (dense ? 8 : 9) : (dense ? 4 : 6)
                        Circle()
                            .fill(isToday ? Color.blankeeAccent
                                  : isLow ? (point.value < 0 ? Color.blankeeDanger : Color.blankeeWarning)
                                  : Color.blankeeWhite)
                            .overlay(Circle().strokeBorder(color, lineWidth: dense ? 1 : 1.5))
                            .frame(width: size, height: size)
                    }
                    .annotation(position: .top, spacing: 2) {
                        if index == window.todayIndex {
                            Text("Today")
                                .font(BlankeeFont.bold(7))
                                .foregroundStyle(Color.blankeeAccent)
                        }
                    }
                    // Under the point, so it never collides with "Today" when
                    // the low is now; kept inside the chart's width when the
                    // low sits at either edge.
                    .annotation(position: .bottom, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if index == lowIndex {
                            Text("Low " + Trends.short(point.value, symbol: symbol)
                                 + " · " + Trends.monthYearLabel(point.date))
                                .font(BlankeeFont.bold(7))
                                .foregroundStyle(point.value < 0 ? Color.blankeeDanger : Color.blankeeWarning)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
            }
        }
        .chartXScale(domain: -0.4...(Double(max(points.count - 1, 1)) + 0.4))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, to: points.count, by: labelStep))) { value in
                if let index = value.as(Int.self), index < points.count {
                    AxisValueLabel(anchor: .top) {
                        Text(Trends.monthYearLabel(points[index].date))
                            .font(BlankeeFont.regular(8))
                            .foregroundStyle(Color.blankeeSecondaryDark)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.black.opacity(0.05))
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(Trends.short(amount, symbol: symbol))
                            .font(BlankeeFont.regular(8))
                            .foregroundStyle(Color.blankeeSecondaryDark)
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, T.inset)
        .padding(.bottom, 4)
        .padding(.top, 8)
    }

    // MARK: Series styling

    private func color(for kind: TrendSeries.Kind) -> Color {
        switch kind {
        case .credit: return Color.blankeeTextDark
        case .checking, .savings: return Color.blankeePrimary
        }
    }

    private func icon(for kind: TrendSeries.Kind) -> String {
        switch kind {
        case .checking: return FAIcon.chartLine
        case .credit: return FAIcon.creditCard
        case .savings: return FAIcon.piggyBank
        }
    }
}

// MARK: - Widget

struct BlankeeTrendWidget: Widget {
    static let kind = "BlankeeTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TrendProvider(kind: Self.kind)) { entry in
            TrendView(entry: entry, kind: Self.kind)
                .containerBackground(for: .widget) {
                    Color.blankeeWhite
                }
        }
        .configurationDisplayName("Balance trend")
        .description("The summary page's graphs: your balance, each card, and savings, month by month.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Gallery sample

extension Trends {
    static let placeholder = Trends(
        currencySymbol: "$",
        series: [
            TrendSeries(id: "checking", kind: .checking, name: "Balance", points: [
                .init(date: "2026-04-30", value: 1840), .init(date: "2026-05-31", value: 2210),
                .init(date: "2026-06-30", value: 1975), .init(date: "2026-07-31", value: 2480),
                .init(date: "2026-08-31", value: 2891), .init(date: "2026-09-30", value: 2640),
                .init(date: "2026-10-31", value: 2990), .init(date: "2026-11-30", value: 3120),
                .init(date: "2026-12-31", value: 2870), .init(date: "2027-01-31", value: 3310),
                .init(date: "2027-02-28", value: 3560), .init(date: "2027-03-31", value: 3720),
            ]),
        ],
        dataVersion: "0"
    )
}

#Preview(as: .systemMedium) {
    BlankeeTrendWidget()
} timeline: {
    TrendEntry(date: Date(), page: 0, state: .loaded(.placeholder))
    TrendEntry(date: Date(), page: 0, state: .message(title: "Signed out",
                                                     detail: "Open Blankee to sign in again."))
}
