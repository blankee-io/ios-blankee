//
//  BlankeeDayBoxWidget.swift
//  BlankeeDayBoxWidget
//
//  A medium widget showing today's day box, and opening dashboard_d when
//  tapped.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct DayBoxEntry: TimelineEntry {
    enum State {
        case loaded(DayBox)
        case message(title: String, detail: String?)
    }

    let date: Date
    /// Days from today that this entry is showing. Carried on the entry so the
    /// nav bar can grey out "today" without reading the store while drawing.
    let offset: Int
    /// Which page of a list widget is showing. Always 0 for the widgets that
    /// have no list.
    let page: Int
    let state: State
}

// MARK: - Provider

struct DayBoxProvider: TimelineProvider {
    /// Which widget's day offset to read. The medium and small widgets page
    /// independently, so they cannot share a key.
    let kind: String

    func placeholder(in context: Context) -> DayBoxEntry {
        DayBoxEntry(date: Date(), offset: 0, page: 0, state: .loaded(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayBoxEntry) -> Void) {
        // The gallery preview has no account behind it, so it gets the sample
        // rather than a sign-in prompt.
        if context.isPreview || !WidgetStore.isConfigured {
            completion(DayBoxEntry(date: Date(), offset: 0, page: 0, state: .loaded(.placeholder)))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayBoxEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: entry))))
        }
    }

    private func load() async -> DayBoxEntry {
        let offset = WidgetStore.dayOffset(for: kind)
        let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        var page = WidgetStore.listPage(for: kind)

        do {
            let box = try await DayBoxService.fetch(for: day)

            // The page buttons move the stored number without knowing how long
            // the list is - only this does. Clamping here, and writing the
            // clamped value back, is what stops a run of taps past the end from
            // needing the same run of taps to get back.
            let pages = DueTodayPaging.pageCount(for: box.dueToday.count)
            let clamped = min(max(0, page), pages - 1)
            if clamped != page {
                WidgetStore.setListPage(clamped, for: kind)
                page = clamped
            }

            return DayBoxEntry(date: Date(), offset: offset, page: page, state: .loaded(box))
        } catch let error as DayBoxError {
            switch error {
            case .notConfigured:
                return DayBoxEntry(date: Date(), offset: offset, page: page,
                                   state: .message(title: "Blankee",
                                                   detail: "Open the app and sign in to set up this widget."))
            case .serverTooOld:
                return DayBoxEntry(date: Date(), offset: offset, page: page,
                                   state: .message(title: "Server needs updating",
                                                   detail: "This Blankee server doesn't have widget support yet."))
            case .unauthorized:
                return DayBoxEntry(date: Date(), offset: offset, page: page,
                                   state: .message(title: "Signed out",
                                                   detail: "Open Blankee to sign in again."))
            case .server, .transport, .badResponse:
                return DayBoxEntry(date: Date(), offset: offset, page: page,
                                   state: .message(title: "Can't reach Blankee",
                                                   detail: error.errorDescription))
            }
        } catch {
            return DayBoxEntry(date: Date(), offset: offset, page: page,
                               state: .message(title: "Can't reach Blankee", detail: nil))
        }
    }

    /// When to ask again.
    ///
    /// Two things have to be true: the figures should not go stale while
    /// someone is looking at the phone, and the box must become *tomorrow's*
    /// box the moment the date turns over. So the next refresh is either the
    /// regular interval or midnight, whichever comes first.
    ///
    /// This is the floor, not the whole story - the app calls
    /// WidgetCenter.reloadAllTimelines() every time a page finishes loading, so
    /// an edit made in the app shows up in seconds rather than at the next tick
    /// of this timer. WidgetKit throttles reloads by its own budget either way;
    /// asking more often than this buys nothing.
    private static func nextRefresh(after entry: DayBoxEntry) -> Date {
        let interval: TimeInterval
        switch entry.state {
        // Nothing is going to fix a signed-out widget except opening the app,
        // and that reloads the timeline itself. Back off rather than hammering
        // a server that is going to say no.
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

// MARK: - Widget

struct BlankeeDayBoxWidget: Widget {
    static let kind = "BlankeeDayBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DayBoxProvider(kind: Self.kind)) { entry in
            DayBoxView(entry: entry, kind: Self.kind)
                .containerBackground(for: .widget) {
                    Color.blankeeBgPage
                }
        }
        .configurationDisplayName("Day")
        .description("A day's box: what came in, what went out, and what is left.")
        .supportedFamilies([.systemMedium])
        // The box is edge-to-edge colour bars, like the page's day container.
        // The system's default margins would inset them and leave the corners
        // looking unfinished.
        .contentMarginsDisabled()
    }
}

/// One cell of the month calendar, from dashboard_m.html.
struct BlankeeMonthDayWidget: Widget {
    static let kind = "BlankeeMonthDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DayBoxProvider(kind: Self.kind)) { entry in
            MonthDayView(entry: entry, kind: Self.kind)
                .containerBackground(for: .widget) {
                    Color.blankeeBgPage
                }
        }
        .configurationDisplayName("Day totals")
        .description("A day at a glance: income, expenses, remainder and savings.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// Everything going out today, expenses and card expenses in one list.
struct BlankeeDueTodayWidget: Widget {
    static let kind = "BlankeeDueTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DayBoxProvider(kind: Self.kind)) { entry in
            DueTodayView(entry: entry, kind: Self.kind)
                .containerBackground(for: .widget) {
                    Color.blankeeWhite
                }
        }
        .configurationDisplayName("Due today")
        .description("Today's expenses and card expenses, in one list.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct BlankeeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlankeeDayBoxWidget()
        BlankeeMonthDayWidget()
        BlankeeDueTodayWidget()
        BlankeeTrendWidget()
    }
}

// MARK: - Gallery sample

extension DayBox {
    /// What the widget gallery shows before it has an account to read. Made up,
    /// deliberately round, and shaped like a real Friday.
    static let placeholder = DayBox(
        date: "2026-08-28",
        dateLabel: "Friday, Aug 28, 2026",
        currencySymbol: "$",
        lastRemainder: 2891.73,
        income: [],
        totalIncome: 0,
        expenses: [
            .init(categoryName: "Excite Credit Union", amount: 375.12,
                  icon: "recurring", isPending: false, isPaid: false, isBucket: false),
            .init(categoryName: "Groceries", amount: 150.00,
                  icon: "recurring", isPending: false, isPaid: false, isBucket: false),
            .init(categoryName: "Spending", amount: 200.00,
                  icon: "recurring", isPending: false, isPaid: false, isBucket: false),
            .init(categoryName: "Farmers Dog", amount: 71.98,
                  icon: "recurring", isPending: false, isPaid: false, isBucket: false),
        ],
        totalExpenses: 892.10,
        remainder: 1999.63,
        remainderState: .aboveThreshold,
        creditAccounts: [],
        savings: 0.40,
        isBeforeMemberSince: false,
        dataVersion: "0"
    )
}

#Preview(as: .systemMedium) {
    BlankeeDayBoxWidget()
} timeline: {
    DayBoxEntry(date: Date(), offset: 0, page: 0, state: .loaded(.placeholder))
    DayBoxEntry(date: Date(), offset: 0, page: 0, state: .message(title: "Signed out",
                                                         detail: "Open Blankee to sign in again."))
}

#Preview(as: .systemSmall) {
    BlankeeMonthDayWidget()
} timeline: {
    DayBoxEntry(date: Date(), offset: 0, page: 0, state: .loaded(.placeholder))
}

#Preview(as: .systemMedium) {
    BlankeeDueTodayWidget()
} timeline: {
    DayBoxEntry(date: Date(), offset: 0, page: 0, state: .loaded(.placeholder))
}
