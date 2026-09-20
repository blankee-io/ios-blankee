// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  DueTodayView.swift
//  BlankeeDayBoxWidget
//
//  Everything going out today, in one list: the day's expenses and its credit
//  account expenses together, which is the one view the page never shows side
//  by side - dashboard_d.html puts credit accounts below their own divider.
//
//  Both come from the same day-box payload, so this costs no extra request.
//

import SwiftUI
import WidgetKit

// MARK: - The list

/// One line of the list, flattened out of the two places expenses live.
struct DueLine: Identifiable {
    let line: DayBox.Line
    /// Set for a credit account expense, so a row can say which card it is on.
    let accountMask: String?

    var id: String { "\(line.categoryName)-\(line.amount)-\(accountMask ?? "")" }
}

extension DayBox {
    /// The day's outgoings, direct and on cards.
    ///
    /// Paid entries are kept rather than filtered out. Dropping them would let
    /// the widget say nothing is due on a day with a dozen settled bills, which
    /// reads as "nothing to pay" and "no data" at exactly the same time - so
    /// they stay, marked the way the day box marks them.
    var dueToday: [DueLine] {
        expenses.map { DueLine(line: $0, accountMask: nil) }
            + creditAccounts.flatMap { account in
                account.entries.map { DueLine(line: $0, accountMask: account.mask) }
            }
    }
}

// MARK: - Paging

/// How many lines fit on a page.
///
/// Fixed rather than measured: the provider clamps the stored page against this
/// same number, and a page size that changed with the geometry would put the
/// two out of step. Kept outside the view because a View is main-actor
/// isolated, and the provider reads this from its own async context.
enum DueTodayPaging {
    static let rowsPerPage = 7

    static func pageCount(for lineCount: Int) -> Int {
        max(1, Int(ceil(Double(lineCount) / Double(rowsPerPage))))
    }
}

// MARK: - View

struct DueTodayView: View {
    let entry: DayBoxEntry
    let kind: String

    private enum D {
        static let headerHeight: CGFloat = 24
        static let rowHeight: CGFloat = 17
        static let inset: CGFloat = 13
        static let columnGap: CGFloat = 3
        static let amountWidth: CGFloat = 82
        static let corner: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Link(destination: blankeeDayBoxDeepLink) {
                content
            }
        }
        .background(Color.blankeeWhite)
        .clipShape(RoundedRectangle(cornerRadius: D.corner, style: .continuous))
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Due Today")
                .font(BlankeeFont.bold(13))
                .foregroundStyle(Color.blankeePrimary)

            if pageCount > 1 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        pageButton(FAIcon.circleLeft, delta: -1, label: "Previous page")
                        pageButton(FAIcon.circleRight, delta: 1, label: "Next page")
                    }
                }
                .padding(.trailing, 5)
            }
        }
        .frame(height: D.headerHeight)
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

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .loaded(let box):
            let lines = box.dueToday
            if lines.isEmpty {
                empty
            } else {
                list(page(of: lines), box: box)
            }
        case .message(let title, let detail):
            MessageView(title: title, detail: detail)
        }
    }

    private func list(_ lines: [DueLine], box: DayBox) -> some View {
        VStack(spacing: 0) {
            ForEach(lines) { due in
                row(due, box: box)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ due: DueLine, box: DayBox) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: DayBoxIcon.symbol(for: due.line.icon))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.blankeeAccent)
                Text(due.line.categoryName)
                    .font(BlankeeFont.regular(11.5))
                    .lineLimit(1)
                // Which card it is on, when it is on one.
                if let mask = due.accountMask, !mask.isEmpty {
                    Text(mask)
                        .font(BlankeeFont.regular(9.5))
                        .foregroundStyle(Color.blankeeSecondary)
                }
            }
            .padding(.leading, D.inset)

            Spacer(minLength: D.columnGap)

            Text(box.format(due.line.amount))
                .font(BlankeeFont.semibold(11.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(due.line.isPending ? 0.55 : 1)
                .frame(width: D.amountWidth, alignment: .trailing)
                .padding(.trailing, D.inset)
        }
        .foregroundStyle(Color.blankeeTextDark)
        .frame(height: D.rowHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if due.line.isPaid {
                PaidBadge().offset(x: -1, y: -4)
            }
        }
    }

    private var empty: some View {
        Text("Nothing due today")
            .font(BlankeeFont.regular(12))
            .foregroundStyle(Color.blankeeSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Paging

    private var lineCount: Int {
        if case .loaded(let box) = entry.state { return box.dueToday.count }
        return 0
    }

    private var pageCount: Int {
        DueTodayPaging.pageCount(for: lineCount)
    }

    private func page(of lines: [DueLine]) -> [DueLine] {
        let start = min(entry.page, pageCount - 1) * DueTodayPaging.rowsPerPage
        guard start < lines.count else { return [] }
        return Array(lines[start..<min(start + DueTodayPaging.rowsPerPage, lines.count)])
    }
}
