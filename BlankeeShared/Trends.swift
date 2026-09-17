//
//  Trends.swift
//  blankee.app
//
//  The balance graphs from dashboard_summary, as the trend widget reads them:
//  one series per graph the page draws - the checking balance, a line per
//  credit account, savings - each reduced to a point a month by the server the
//  same way the page's filterToMonthly() does it.
//

import Foundation

struct TrendPoint: Decodable, Identifiable {
    /// YYYY-MM-DD, the last day recorded in that month.
    let date: String
    let value: Double

    var id: String { date }
}

struct TrendSeries: Decodable, Identifiable {
    enum Kind: String, Decodable {
        case checking, credit, savings
    }

    let id: String
    let kind: Kind
    let name: String
    let points: [TrendPoint]
    /// The lowest *day* from today on, which the month points cannot show:
    /// a month's point is its last day, and the balance bottoms out somewhere
    /// inside the month. Absent from servers older than 1.43.9.
    let low: TrendPoint?

    init(id: String, kind: Kind, name: String, points: [TrendPoint], low: TrendPoint? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.points = points; self.low = low
    }
}

struct Trends: Decodable {
    let currencySymbol: String
    /// In the page's order: checking, then the credit accounts, then savings.
    /// The widget's arrows walk this list and wrap at both ends.
    let series: [TrendSeries]
    let dataVersion: String

    private enum CodingKeys: String, CodingKey {
        case currencySymbol = "currency_symbol"
        case series
        case dataVersion = "data_version"
    }

    init(currencySymbol: String, series: [TrendSeries], dataVersion: String) {
        self.currencySymbol = currencySymbol
        self.series = series
        self.dataVersion = dataVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currencySymbol = try c.decodeIfPresent(String.self, forKey: .currencySymbol) ?? "$"
        series = try c.decodeIfPresent([TrendSeries].self, forKey: .series) ?? []
        // The server's version stamp has been both a number and a string; the
        // widget only ever compares it, so either shape is fine.
        if let text = try? c.decode(String.self, forKey: .dataVersion) {
            dataVersion = text
        } else if let number = try? c.decode(Int.self, forKey: .dataVersion) {
            dataVersion = String(number)
        } else {
            dataVersion = "0"
        }
    }
}

// MARK: - The window a widget can show

extension TrendSeries {

    struct Window {
        let points: [TrendPoint]
        /// Index into `points` of the month that holds today, if it is in range.
        let todayIndex: Int?
    }

    /// The page scrolls its graph to today and lets it run on to the end of the
    /// forecast; a widget cannot scroll, so it shows that whole stretch at
    /// once: today's month at the left edge, then every month the server sent,
    /// out to the last one. How far that is - December three years on - is the
    /// server's rule, and the widget does not repeat it. What is behind today
    /// is already in the bank, and leaving it off buys the room for what is
    /// ahead.
    ///
    /// A `count` caps the window when a caller wants one; the widget passes
    /// none.
    func window(around today: Date = Date(), count: Int? = nil, monthsBack: Int = 0) -> Window {
        let sorted = points.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return Window(points: [], todayIndex: nil) }

        let thisMonth = String(WidgetAPI.isoDay.string(from: today).prefix(7))
        // The month holding today, or failing that the last month before it -
        // the same fallback the page uses when nothing matches exactly.
        var todayIdx = sorted.firstIndex { $0.date.hasPrefix(thisMonth) }
        if todayIdx == nil {
            todayIdx = sorted.lastIndex { $0.date < thisMonth }
        }

        var start = max(0, (todayIdx ?? 0) - monthsBack)
        var end = sorted.count
        if let count {
            end = min(sorted.count, start + count)
            if end - start < count {
                start = max(0, end - count)
                end = min(sorted.count, start + count)
            }
        }

        let slice = Array(sorted[start..<end])
        let index = todayIdx.map { $0 - start }.flatMap { (0..<slice.count).contains($0) ? $0 : nil }
        return Window(points: slice, todayIndex: index)
    }
}

// MARK: - Formatting

extension Trends {

    /// "$1.2K", "$15K", "-$340" - the axis labels the page draws.
    static func short(_ value: Double, symbol: String) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        let body: String
        if magnitude >= 1_000_000 {
            body = trimmed(magnitude / 1_000_000) + "M"
        } else if magnitude >= 1_000 {
            body = trimmed(magnitude / 1_000) + "K"
        } else {
            body = String(Int(magnitude.rounded()))
        }
        return sign + symbol + body
    }

    /// "$2,891.73", for the figure under the title.
    static func full(_ value: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: NSNumber(value: abs(value))) ?? String(format: "%.2f", abs(value))
        return (value < 0 ? "-" : "") + symbol + text
    }

    /// 1.2 stays 1.2, 15.0 becomes 15.
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// "Sep" from "2026-09-30".
    static func monthLabel(_ isoDate: String) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let parts = isoDate.split(separator: "-")
        guard parts.count >= 2, let month = Int(parts[1]), (1...12).contains(month) else { return "" }
        return months[month - 1]
    }

    /// "Sep 23 '26" - a day, for the low.
    static func dayLabel(_ isoDate: String) -> String {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]) else { return monthYearLabel(isoDate) }
        return monthLabel(isoDate) + " " + String(day) + " '" + String(parts[0].suffix(2))
    }

    /// "Sep '26" - the page's daily label shape, which is the one that still
    /// reads when the axis spans several years.
    static func monthYearLabel(_ isoDate: String) -> String {
        let year = isoDate.split(separator: "-").first.map(String.init) ?? ""
        return monthLabel(isoDate) + " '" + String(year.suffix(2))
    }
}

// MARK: - Fetching

enum TrendService {
    static func fetch() async throws -> Trends {
        try await WidgetAPI.fetch(Trends.self, path: "/api/widget/trends", definesSupport: false)
    }
}
