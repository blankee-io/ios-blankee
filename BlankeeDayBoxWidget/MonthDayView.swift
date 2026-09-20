// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  MonthDayView.swift
//  BlankeeDayBoxWidget
//
//  One cell of the month calendar, as the small widget.
//
//  Copied from dashboard_m.html's day cell rather than invented: the weekday
//  strip in secondary-dark, the date number on the page background between two
//  grey rules, then income, expenses, remainder and savings. The web app hides
//  its I/E/R/S letters (`.dashboard-m-label` is `display: none`), so only the
//  figures show here too, centred the way `.dashboard-m-value` centres them.
//

import SwiftUI
import WidgetKit

private enum M {
    static let corner: CGFloat = 10
    static let rule: CGFloat = 2
    static let navHeight: CGFloat = 30
}

struct MonthDayView: View {
    let entry: DayBoxEntry
    let kind: String

    var body: some View {
        VStack(spacing: 0) {
            DayNavBar(kind: kind,
                      glyphSize: 17,
                      centerGlyphSize: 21,
                      buttonSize: 28,
                      spacing: 12)
                .frame(height: M.navHeight)

            Link(destination: blankeeDayBoxDeepLink) {
                switch entry.state {
                case .loaded(let box):
                    cell(box)
                case .message(let title, let detail):
                    MessageCard(title: title, detail: detail)
                }
            }
        }
    }

    private func cell(_ box: DayBox) -> some View {
        VStack(spacing: 0) {
            // Weekday, then the date number. Split out of date_label so the
            // cell reads the way the calendar does.
            Text(weekday(box).uppercased())
                .font(BlankeeFont.bold(11))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(Color.blankeeSecondaryDark)

            Text(dayNumber(box))
                .font(BlankeeFont.bold(15))
                .foregroundStyle(Color.blankeeTextDark)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Color.blankeeBgPage)
                .overlay(sideRules)

            // Painted, not transparent. The calendar leaves these rows clear
            // because a table cell sits behind them; a widget has the system's
            // container behind it instead, which shows through as grey. So they
            // take the page background explicitly, the same as the date number
            // above.
            //
            // A day with no income or expenses shows an empty row rather than a
            // zero, which is what .zero-value does on the page.
            value(box.totalIncome == 0 ? nil : box.format(box.totalIncome),
                  color: .blankeePrimary,
                  background: .blankeeBgPage)
                .overlay(sideRules)

            value(box.totalExpenses == 0 ? nil : box.format(box.totalExpenses),
                  color: .blankeeAccent,
                  background: .blankeeBgPage)
                .overlay(sideRules)

            value(box.format(box.remainder), color: .white,
                  background: Color.blankeeSecondary)
                .overlay(alignment: .topTrailing) {
                    if box.remainderState == .negative || box.remainderState == .belowThreshold {
                        CornerBadge(mark: .exclamation,
                                    background: box.remainderState == .negative
                                        ? .blankeeDanger : .blankeeWarning,
                                    diameter: 14)
                            .offset(x: -3, y: -7)
                    }
                }
                .zIndex(1)

            value(box.format(box.savings), color: .white, background: Color.blankeePrimary)
        }
        .clipShape(RoundedRectangle(cornerRadius: M.corner, style: .continuous))
        .opacity(box.isBeforeMemberSince ? 0.45 : 1)
    }

    /// A nil figure keeps the row's height and loses its text, the way the
    /// calendar's `visibility: hidden` does.
    private func value(_ text: String?, color: Color, background: Color) -> some View {
        Text(text ?? "")
            .font(BlankeeFont.bold(12))
            .foregroundStyle(color)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
    }

    /// The 2px grey edges the calendar draws down each cell.
    private var sideRules: some View {
        HStack {
            Rectangle().fill(Color.blankeeSecondary).frame(width: M.rule)
            Spacer(minLength: 0)
            Rectangle().fill(Color.blankeeSecondary).frame(width: M.rule)
        }
    }

    // date_label is "Saturday, Aug 29, 2026" - enough to split without asking
    // the server for the parts separately.
    private func weekday(_ box: DayBox) -> String {
        String(box.dateLabel.split(separator: ",").first ?? "").prefix(3).description
    }

    private func dayNumber(_ box: DayBox) -> String {
        box.date.split(separator: "-").last.map { String(Int($0) ?? 0) } ?? ""
    }
}

/// The small widget's version of an error: no room for a detail line, so the
/// title carries it.
struct MessageCard: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(BlankeeFont.semibold(12))
                .foregroundStyle(Color.blankeeTextDark)
            if let detail {
                Text(detail)
                    .font(BlankeeFont.regular(9.5))
                    .foregroundStyle(Color.blankeeSecondaryDark)
            }
        }
        .multilineTextAlignment(.center)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blankeeBgPage)
        .clipShape(RoundedRectangle(cornerRadius: M.corner, style: .continuous))
    }
}
