// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  UpcomingBillsView.swift
//  BlankeeDayBoxWidget
//
//  The Summary page's Upcoming Bills, as a widget: the accent header with the
//  date of the last bank sync, the page's three filter questions as buttons
//  under it, and the rows - pinned first, then soonest first - with the last
//  occurrence on the left, dimmed, and the one coming up on the right.
//
//  Each filter button steps through its answers ("all" first) and the widget
//  keeps its own choices, so a medium one can show cards and a large one
//  everything. The arrows page when there are more rows than fit.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intent

/// One filter button: the next answer to its question. Back to the first page,
/// since the old page number means nothing in a different list.
struct CycleBillFilterIntent: AppIntent {
    static var title: LocalizedStringResource = "Filter the bills"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Widget kind") var kind: String
    @Parameter(title: "Question") var question: String

    init() {}

    init(kind: String, question: BillFilter.Question) {
        self.kind = kind
        self.question = question.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let q = BillFilter.Question(rawValue: question) {
            BillFilter.advance(q, for: kind)
            WidgetStore.setListPage(0, for: kind)
        }
        return .result()
    }
}

// MARK: - Timeline entry

struct UpcomingBillsEntry: TimelineEntry {
    enum State {
        case loaded(UpcomingBills)
        case message(title: String, detail: String?)
    }

    let date: Date
    let page: Int
    let filter: BillFilter.Selection
    let state: State
}

/// Rows a page holds, by size. Fixed, so the provider and the view agree.
enum UpcomingBillsPaging {
    static func rowsPerPage(_ family: WidgetFamily) -> Int {
        family == .systemLarge ? 9 : 3
    }

    static func pageCount(rows: Int, family: WidgetFamily) -> Int {
        max(1, Int(ceil(Double(rows) / Double(rowsPerPage(family)))))
    }
}

// MARK: - Provider

struct UpcomingBillsProvider: TimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> UpcomingBillsEntry {
        UpcomingBillsEntry(date: Date(), page: 0, filter: .init(), state: .loaded(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingBillsEntry) -> Void) {
        if context.isPreview || !WidgetStore.isConfigured {
            completion(UpcomingBillsEntry(date: Date(), page: 0, filter: .init(), state: .loaded(.placeholder)))
            return
        }
        Task { completion(await load(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingBillsEntry>) -> Void) {
        Task {
            let entry = await load(family: context.family)
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: entry))))
        }
    }

    private func load(family: WidgetFamily) async -> UpcomingBillsEntry {
        let filter = BillFilter.selection(for: kind)
        var page = WidgetStore.listPage(for: kind)
        do {
            let bills = try await UpcomingBillsService.fetch()
            // As the Due Today list does: the arrows move the number blindly,
            // and only here is the length of the filtered list known.
            let shown = bills.rows.filter(filter.matches).count
            let clamped = min(max(0, page), UpcomingBillsPaging.pageCount(rows: shown, family: family) - 1)
            if clamped != page {
                WidgetStore.setListPage(clamped, for: kind)
                page = clamped
            }
            return UpcomingBillsEntry(date: Date(), page: page, filter: filter, state: .loaded(bills))
        } catch let error as DayBoxError {
            let (title, detail) = error.widgetMessage
            return UpcomingBillsEntry(date: Date(), page: page, filter: filter, state: .message(title: title, detail: detail))
        } catch {
            return UpcomingBillsEntry(date: Date(), page: page, filter: filter,
                                      state: .message(title: "Can't reach Blankee", detail: nil))
        }
    }

    /// The other widgets' schedule: quarter-hourly with data, half-hourly with
    /// a message, and always by midnight, when "this month" and what is next
    /// can change.
    private static func nextRefresh(after entry: UpcomingBillsEntry) -> Date {
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

// MARK: - View

struct UpcomingBillsView: View {
    let entry: UpcomingBillsEntry
    let kind: String
    @Environment(\.widgetFamily) private var family

    private enum U {
        static let headerHeight: CGFloat = 26
        static let filterHeight: CGFloat = 26
        static let rowHeight: CGFloat = 32
        static let inset: CGFloat = 10
        static let sideWidth: CGFloat = 78
        static let corner: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Link(destination: blankeeSummaryDeepLink) {
                content
            }
        }
        .background(Color.blankeeWhite)
        .clipShape(RoundedRectangle(cornerRadius: U.corner, style: .continuous))
    }

    // MARK: Header - the page's accent bar

    private var header: some View {
        HStack(spacing: 6) {
            Text(FAIcon.receipt)
                .font(BlankeeFont.awesome(11))
            Text("Upcoming Bills")
                .font(BlankeeFont.bold(13))
                .lineLimit(1)
            if case .loaded(let bills) = entry.state, let asOf = bills.asOf {
                Text("as of " + asOf.label)
                    .font(BlankeeFont.regular(10))
                    .opacity(0.9)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if pageCount > 1 {
                HStack(spacing: 2) {
                    pageButton(FAIcon.circleLeft, delta: -1, label: "Previous page")
                    pageButton(FAIcon.circleRight, delta: 1, label: "Next page")
                }
            }
        }
        .foregroundStyle(Color.blankeeTextLight)
        .padding(.leading, U.inset)
        .padding(.trailing, 5)
        .frame(height: U.headerHeight)
        .frame(maxWidth: .infinity)
        .background(Color.blankeeAccent)
    }

    private func pageButton(_ icon: String, delta: Int, label: String) -> some View {
        Button(intent: ShiftPageIntent(kind: kind, delta: delta)) {
            Text(icon)
                .font(BlankeeFont.awesome(14))
                .foregroundStyle(Color.blankeeTextLight)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: The filter buttons

    private var filterBar: some View {
        HStack(spacing: 5) {
            Text(FAIcon.filter)
                .font(BlankeeFont.awesome(9))
                .foregroundStyle(entry.filter.isFiltering ? Color.blankeePrimary : Color.blankeeSecondary)
            ForEach(BillFilter.Question.allCases, id: \.self) { question in
                chip(question)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, U.inset)
        .frame(height: U.filterHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.blankeeSecondaryLighter).frame(height: 1)
        }
    }

    private func chip(_ question: BillFilter.Question) -> some View {
        let value = entry.filter.value(question)
        let active = value != "all"
        return Button(intent: CycleBillFilterIntent(kind: kind, question: question)) {
            Text(BillFilter.label(question, value))
                .font(BlankeeFont.semibold(10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(active ? Color.blankeeTextLight : Color.blankeeTextDark)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(active ? Color.blankeePrimary : Color.blankeeWhite))
                .overlay(Capsule().strokeBorder(active ? Color.blankeePrimary : Color.blankeeSecondaryHover, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: " + BillFilter.label(question, value))
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .loaded(let bills):
            let shown = bills.rows.filter(entry.filter.matches)
            if bills.rows.isEmpty {
                empty("No recurring bills yet")
            } else if shown.isEmpty {
                empty("Nothing matches the filter")
            } else {
                VStack(spacing: 0) {
                    ForEach(page(of: shown)) { row in
                        billRow(row, bills: bills)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .message(let title, let detail):
            MessageCard(title: title, detail: detail)
                .padding(U.inset)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(BlankeeFont.regular(11))
            .foregroundStyle(Color.blankeeSecondaryDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The page's row: tinted for the budget, white for a card with its name,
    /// teal for income, the pin on a pinned one, then both sides.
    private func billRow(_ row: BillRow, bills: UpcomingBills) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if row.pinned {
                    Text(FAIcon.thumbtack)
                        .font(BlankeeFont.awesome(8))
                        .foregroundStyle(Color.blankeePrimary)
                }
                if let card = row.accountName, !card.isEmpty {
                    Text(card)
                        .font(BlankeeFont.semibold(8))
                        .foregroundStyle(Color.blankeeTextDark)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.blankeeSecondaryLighter))
                        .fixedSize()
                }
                Text(row.name)
                    .font(BlankeeFont.semibold(11))
                    .foregroundStyle(Color.blankeeTextDark)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            side(row.last, isBill: row.isBill, income: row.isIncome, bills: bills)
                .opacity(0.5)
            Rectangle().fill(Color.blankeeSecondaryHover).frame(width: 1, height: U.rowHeight - 12)
            side(row.upcoming, isBill: row.isBill, income: row.isIncome, bills: bills)
        }
        .padding(.horizontal, U.inset)
        .frame(height: U.rowHeight)
        .frame(maxWidth: .infinity)
        .background(row.isIncome ? Color.blankeePrimaryLighter
                    : (row.isCard ? Color.blankeeWhite : Color.blankeeAccentLighter))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.blankeeSecondaryLighter).frame(height: 1)
        }
    }

    /// One side: the date, then a bill's paid or unpaid mark, or a bucket's
    /// bar and what is left. A missing side is a dash, as on the page. An
    /// income says it in its own words: received or expected, still to come.
    @ViewBuilder
    private func side(_ side: BillSide?, isBill: Bool, income: Bool, bills: UpcomingBills) -> some View {
        VStack(spacing: 1) {
            if let side {
                Text(side.date.map(Self.dayLabel) ?? "")
                    .font(BlankeeFont.regular(8))
                    .foregroundStyle(Color.blankeeSecondaryDark)
                if isBill {
                    Text(FAIcon.handHoldingDollar)
                        .font(BlankeeFont.awesome(10))
                        .foregroundStyle(side.paid ? Color.blankeeSuccess : Color.blankeeDanger)
                        .accessibilityLabel(income ? (side.paid ? "Received" : "Expected")
                                                   : (side.paid ? "Paid" : "Unpaid"))
                } else {
                    bucket(side, income: income, bills: bills)
                }
            } else {
                Text("—")
                    .font(BlankeeFont.regular(10))
                    .foregroundStyle(Color.blankeeSecondary)
            }
        }
        .frame(width: U.sideWidth)
    }

    /// A bucket spent down - or, for income, filling up: the bar is what has
    /// come in, and going past it is good news rather than overspending.
    private func bucket(_ side: BillSide, income: Bool, bills: UpcomingBills) -> some View {
        let spent = side.originalAmount - side.currentAmount
        let share = side.originalAmount > 0 ? min(max(spent / side.originalAmount, 0), 1) : 0
        let over = side.currentAmount < 0
        let barColor = income ? Color.blankeePrimary
            : (over || share >= 1 ? Color.blankeeDanger : Color.blankeeSuccess)
        let text = over
            ? bills.format(abs(side.currentAmount)) + (income ? " extra" : " over")
            : bills.format(side.currentAmount) + (income ? " to come" : " left")
        return VStack(spacing: 1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.blankeeSecondaryHover)
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 3)
            Text(text)
                .font(BlankeeFont.semibold(8))
                .foregroundStyle(over && !income ? Color.blankeeDanger : Color.blankeePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// "Oct 16" from "2026-10-16".
    private static func dayLabel(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]) else { return iso }
        return Trends.monthLabel(iso) + " " + String(day)
    }

    // MARK: Paging

    private var shownCount: Int {
        if case .loaded(let bills) = entry.state { return bills.rows.filter(entry.filter.matches).count }
        return 0
    }

    private var pageCount: Int {
        UpcomingBillsPaging.pageCount(rows: shownCount, family: family)
    }

    private func page(of rows: [BillRow]) -> [BillRow] {
        let size = UpcomingBillsPaging.rowsPerPage(family)
        let start = min(entry.page, pageCount - 1) * size
        guard start < rows.count else { return [] }
        return Array(rows[start..<min(start + size, rows.count)])
    }
}

// MARK: - Widget

struct BlankeeUpcomingBillsWidget: Widget {
    static let kind = "BlankeeUpcomingBillsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UpcomingBillsProvider(kind: Self.kind)) { entry in
            UpcomingBillsView(entry: entry, kind: Self.kind)
                .containerBackground(for: .widget) {
                    Color.blankeeWhite
                }
        }
        .configurationDisplayName("Upcoming bills")
        .description("The summary page's bills, buckets and income, last and next, filtered your way.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Gallery sample

extension UpcomingBills {
    static let placeholder = UpcomingBills(
        currencySymbol: "$",
        asOf: nil,
        rows: [
            BillRow.sample("e:1", "Rent", pinned: true, last: ("2026-09-01", 1200, 0, true), next: ("2026-10-01", 1200, 1200, false)),
            BillRow.sample("c:2", "Streaming", card: "Visa", last: ("2026-09-06", 17.99, 0, true), next: ("2026-10-06", 17.99, 17.99, false)),
            BillRow.sample("e:3", "Groceries", bill: false, last: ("2026-09-25", 150, -12, false), next: ("2026-10-09", 150, 64.5, false)),
            BillRow.sample("e:4", "Electric", last: ("2026-09-12", 96, 0, true), next: ("2026-10-12", 96, 96, false)),
            BillRow.sample("i:5", "Paycheck", income: true, last: ("2026-09-30", 2100, 0, true), next: ("2026-10-15", 2100, 2100, false)),
        ],
        dataVersion: "0"
    )
}

private extension BillRow {
    static func sample(_ key: String, _ name: String, card: String? = nil, bill: Bool = true, pinned: Bool = false,
                       income: Bool = false,
                       last: (String, Double, Double, Bool), next: (String, Double, Double, Bool)) -> BillRow {
        BillRow(key: key, flow: income ? "income" : "expense", name: name, accountName: card, isBill: bill, pinned: pinned,
                last: BillSide(date: last.0, originalAmount: last.1, currentAmount: last.2, paid: last.3),
                upcoming: BillSide(date: next.0, originalAmount: next.1, currentAmount: next.2, paid: next.3),
                paidThisMonth: false, dueThisMonth: bill)
    }
}

#Preview(as: .systemLarge) {
    BlankeeUpcomingBillsWidget()
} timeline: {
    UpcomingBillsEntry(date: Date(), page: 0, filter: .init(), state: .loaded(.placeholder))
}
