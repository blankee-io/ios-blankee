//
//  DayBoxView.swift
//  BlankeeDayBoxWidget
//
//  Today's day container, drawn the way dashboard_d.html draws it: the dark
//  date header, then the stack of full-bleed rows - last remainder, income
//  lines, total income, expense lines, total expenses, remainder - and the teal
//  savings bar closing it off.
//
//  Colours come from BlankeeTheme, which is style.css's :root in Swift, so the
//  widget and the page stay the same colour without anyone maintaining a second
//  palette.
//

import SwiftUI
import WidgetKit

// MARK: - Metrics

private enum Metrics {
    static let headerHeight: CGFloat = 32
    static let barHeight: CGFloat = 16
    static let lineHeight: CGFloat = 14
    static let corner: CGFloat = 8
    /// Right-hand breathing room, shared by every row so their right edges are
    /// the same edge.
    static let inset: CGFloat = 13
    /// The page puts amounts in a fixed 100px column (.dashboard-d-amount-cell)
    /// and lets the label column flex beside it (.dashboard-d-label-cell,
    /// flex: 3), both right-aligned. Same idea here, at a width that fits a
    /// six-figure balance rather than the page's 875px scale.
    static let amountWidth: CGFloat = 82
    /// .dashboard-d-amount-cell's padding-left.
    static let columnGap: CGFloat = 3
    static let barFont: CGFloat = 11.5
    static let lineFont: CGFloat = 10.5

    /// The five summary bars are the day box's skeleton and are always drawn;
    /// entry lines get whatever height is left over. Which is the same order of
    /// priority the page has, just made explicit because a medium widget is
    /// 158pt tall and a real day is not.
    static let fixedBars = 5  // last remainder, total income, total expenses, remainder, savings
}

// MARK: - Icons

/// The glyphs dashboard_d.html puts in front of a category name. SF Symbols
/// rather than Font Awesome: the extension does not carry the web fonts, and
/// these are the closest equivalents at 10pt where the difference stops being
/// visible anyway.
enum DayBoxIcon {
    static func symbol(for name: String) -> String {
        switch name {
        case "starting-balance":   return "flag.checkered"
        case "bud":                return "leaf"
        case "savings", "savings-recurring": return "banknote"
        case "recurring":          return "arrow.trianglehead.2.clockwise"
        case "credit", "credit-recurring":   return "creditcard"
        case "locked":             return "lock"
        default:                   return "folder"
        }
    }
}

// MARK: - Corner badges

/// The small circles the page pins to the corner of an amount cell: an
/// exclamation for a remainder that is negative or below threshold
/// (`.negative::before` / `.below-threshold::before`), a tick for an entry that
/// has been paid (`.paid::after`). All three are an 11px circle with a white
/// mark in it.
struct CornerBadge: View {
    enum Mark {
        case exclamation
        case check
    }

    let mark: Mark
    let background: Color
    var diameter: CGFloat = 13

    var body: some View {
        Text(glyph)
            .font(font)
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(background))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    }

    private var glyph: String {
        switch mark {
        case .exclamation: return "!"
        case .check: return FAIcon.check
        }
    }

    /// The page writes its exclamation as plain text and its tick as a Font
    /// Awesome glyph, so the fonts differ the same way here.
    private var font: Font {
        switch mark {
        case .exclamation: return BlankeeFont.bold(diameter * 0.66)
        case .check: return BlankeeFont.awesome(diameter * 0.55)
        }
    }
}

/// `.paid::after` - a tick on --success, for an entry already paid.
struct PaidBadge: View {
    var diameter: CGFloat = 12

    var body: some View {
        CornerBadge(mark: .check, background: .blankeeSuccess, diameter: diameter)
    }
}

// MARK: - Rows

/// One of the coloured full-width bars: a label on the left, a figure hard
/// against the right edge.
private struct SummaryBar: View {
    let label: String
    let value: String
    let background: Color
    var showsWarningDot: Bool = false
    var warningColor: Color = .blankeeDanger

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(label)
                .font(BlankeeFont.regular(Metrics.barFont))
                .lineLimit(1)
                .padding(.trailing, Metrics.columnGap)
            Text(value)
                .font(BlankeeFont.semibold(Metrics.barFont))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Metrics.amountWidth, alignment: .trailing)
        }
        .padding(.trailing, Metrics.inset)
        .foregroundStyle(.white)
        // Flexible rather than fixed. The bars share out whatever the entry
        // lines do not use, so a quiet day does not leave a band of empty
        // background above Savings.
        .frame(minHeight: Metrics.barHeight, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(alignment: .topTrailing) {
            if showsWarningDot {
                // Anchored to the bar rather than to the figure, and lifted by
                // half its own height, so it straddles the join with the row
                // above instead of floating somewhere inside this one.
                CornerBadge(mark: .exclamation, background: warningColor)
                    .offset(x: -2, y: -6.5)
            }
        }
    }
}

/// One income or expense entry, zebra-striped by position the way the page's
/// :nth-child rules stripe them.
private struct EntryLine: View {
    let line: DayBox.Line
    let value: String
    let background: Color

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            // The label column: icon and name travel together, so the name
            // ends where every other row's label ends.
            HStack(spacing: 3) {
                Image(systemName: DayBoxIcon.symbol(for: line.icon))
                    .font(.system(size: Metrics.lineFont - 1.5))
                Text(line.categoryName)
                    .font(BlankeeFont.regular(Metrics.lineFont))
                    .lineLimit(1)
            }
            .padding(.trailing, Metrics.columnGap)

            Text(value)
                .font(BlankeeFont.semibold(Metrics.lineFont))
                // A pending entry is one the bank imported but nobody has
                // categorised; the page greys it out rather than hiding it.
                .opacity(line.isPending ? 0.55 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Metrics.amountWidth, alignment: .trailing)
        }
        .padding(.trailing, Metrics.inset)
        .foregroundStyle(Color.blankeeTextDark)
        .frame(height: Metrics.lineHeight)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(alignment: .topTrailing) {
            if line.isPaid {
                // Same badge, same corner and same lift as the warning mark on
                // the summary bars: in the right-hand padding, clear of the
                // figure, straddling the join with the row above.
                PaidBadge(diameter: 13).offset(x: -2, y: -6.5)
            }
        }
    }
}

// MARK: - The box

struct DayBoxView: View {
    let entry: DayBoxEntry
    let kind: String

    var body: some View {
        VStack(spacing: 0) {
            // The navigation rides in the date header rather than above it. A
            // row of its own cost 22pt on a widget only 158pt tall, which is
            // an entry line and a half - and the header had the room going
            // spare.
            header

            // Link rather than .widgetURL, so opening the app is the box's own
            // job. widgetURL covers the whole widget, which would put the tap
            // target underneath the navigation buttons.
            Link(destination: blankeeDayBoxDeepLink) {
                switch entry.state {
                case .loaded(let box):
                    dayBox(box)
                case .message(let title, let detail):
                    MessageView(title: title, detail: detail)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
    }

    /// The dark date bar, with the day navigation sitting at its right end.
    ///
    /// Drawn in both states on purpose. With the buttons anywhere else, a day
    /// whose request failed would have no way back to one that works.
    private var header: some View {
        ZStack {
            Text(headerLabel)
                .font(BlankeeFont.semibold(12))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                DayNavBar(kind: kind,
                          glyphSize: 16,
                          centerGlyphSize: 19,
                          buttonSize: 27,
                          spacing: 3)
            }
            .padding(.trailing, 3)
        }
        .frame(height: Metrics.headerHeight)
        .frame(maxWidth: .infinity)
        .background(Color.blankeeTextDark)
    }

    /// The server's label when there is one; otherwise the day this entry was
    /// asking about, worked out locally so the bar is never blank.
    private var headerLabel: String {
        if case .loaded(let box) = entry.state { return box.dateLabel }
        let day = Calendar.current.date(byAdding: .day, value: entry.offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: day)
    }

    // MARK: Loaded

    private func dayBox(_ box: DayBox) -> some View {
        GeometryReader { geometry in
            let available = geometry.size.height
                - CGFloat(Metrics.fixedBars) * Metrics.barHeight
            let budget = max(0, Int(available / Metrics.lineHeight))
            let plan = LinePlan(income: box.income.count, expenses: box.expenses.count, budget: budget)

            VStack(spacing: 0) {
                SummaryBar(label: "Last remainder:",
                           value: box.format(box.lastRemainder),
                           background: .blankeeSecondary)

                lines(Array(box.income.prefix(plan.income)),
                      odd: .blankeePrimaryHover, even: .blankeePrimaryLighter,
                      box: box)

                SummaryBar(label: overflowLabel("Total Income:", hidden: plan.hiddenIncome),
                           value: box.format(box.totalIncome),
                           background: .blankeePrimary)

                lines(Array(box.expenses.prefix(plan.expenses)),
                      odd: .blankeeAccentHover, even: .blankeeAccentLighter,
                      box: box)

                SummaryBar(label: overflowLabel("Total Expenses:", hidden: plan.hiddenExpenses),
                           value: box.format(box.totalExpenses),
                           background: .blankeeAccent)

                SummaryBar(label: "Remainder:",
                           value: box.format(box.remainder),
                           background: .blankeeSecondary,
                           showsWarningDot: box.remainderState == .negative
                                         || box.remainderState == .belowThreshold,
                           warningColor: box.remainderState == .negative
                                         ? .blankeeDanger : .blankeeWarning)

                SummaryBar(label: "Savings:",
                           value: box.format(box.savings),
                           background: .blankeePrimary)
            }
            // The page dims a day before the user joined; nothing on it is real.
            .opacity(box.isBeforeMemberSince ? 0.45 : 1)
        }
    }

    private func lines(_ items: [DayBox.Line], odd: Color, even: Color, box: DayBox) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, line in
            EntryLine(line: line,
                      value: box.format(line.amount),
                      background: index.isMultiple(of: 2) ? odd : even)
        }
    }

    /// Says so when lines were dropped, rather than letting a total silently
    /// disagree with the rows above it.
    private func overflowLabel(_ label: String, hidden: Int) -> String {
        hidden > 0 ? "+\(hidden) more   \(label)" : label
    }
}

/// How many income and expense lines fit, given how many rows there is room
/// for. Both groups keep at least one line when they have any, so a day never
/// shows its expenses while pretending it had no income.
private struct LinePlan {
    let income: Int
    let expenses: Int
    let hiddenIncome: Int
    let hiddenExpenses: Int

    init(income incomeCount: Int, expenses expenseCount: Int, budget: Int) {
        let total = incomeCount + expenseCount

        if total <= budget {
            income = incomeCount
            expenses = expenseCount
        } else if budget <= 1 {
            // Room for one line at most: give it to whichever group has any,
            // preferring expenses, which is where a day's detail usually is.
            expenses = expenseCount > 0 ? min(budget, 1) : 0
            income = (expenses == 0 && incomeCount > 0) ? min(budget, 1) : 0
        } else {
            // Share the room in proportion, but never starve a group that has
            // something to show.
            let incomeShare = Int((Double(budget) * Double(incomeCount) / Double(total)).rounded())
            var shownIncome = min(incomeCount, max(incomeCount > 0 ? 1 : 0, incomeShare))
            var shownExpenses = min(expenseCount, budget - shownIncome)
            if expenseCount > 0 && shownExpenses == 0 {
                shownExpenses = 1
                shownIncome = min(shownIncome, budget - 1)
            }
            income = shownIncome
            expenses = shownExpenses
        }

        hiddenIncome = incomeCount - income
        hiddenExpenses = expenseCount - expenses
    }
}

// MARK: - Placeholder / error

/// Shared with the other medium widgets, so a signed-out or unreachable state
/// reads the same wherever it turns up.
struct MessageView: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(BlankeeFont.semibold(13))
                .foregroundStyle(Color.blankeeTextDark)
            if let detail {
                Text(detail)
                    .font(BlankeeFont.regular(11))
                    .foregroundStyle(Color.blankeeSecondaryDark)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blankeeBgPage)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
    }
}
