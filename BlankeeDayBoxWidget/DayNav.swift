// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  DayNav.swift
//  BlankeeDayBoxWidget
//
//  Stepping a widget between days, and the row of buttons that does it.
//
//  A widget cannot be swiped - it is an archived rendering, not a live view, so
//  there are no gestures to attach to. Buttons backed by an AppIntent are the
//  only way to move between days without leaving the home screen: the intent
//  runs, the stored offset moves, and WidgetKit redraws.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents

/// Steps one widget kind forward or back a day.
struct ShiftDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show a different day"
    /// Keeps this out of Shortcuts and Spotlight. It is a button on a widget,
    /// not something anyone would build an automation from.
    static var isDiscoverable: Bool = false

    @Parameter(title: "Widget kind") var kind: String
    @Parameter(title: "Days") var delta: Int

    init() {}

    init(kind: String, delta: Int) {
        self.kind = kind
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        WidgetStore.shiftDayOffset(by: delta, for: kind)
        return .result()
    }
}

/// Back to today - the middle button, matching the page's "Go to Current Week".
struct ShowTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show today"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Widget kind") var kind: String

    init() {}

    init(kind: String) {
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        WidgetStore.setDayOffset(0, for: kind)
        return .result()
    }
}

/// Pages a list widget forward or back.
///
/// Deliberately unbounded: the intent has no idea how long the list is, so it
/// just moves the number and lets the provider clamp it against the real page
/// count on the next load. Trying to bound it here would mean the button
/// knowing something only the fetched data knows.
struct ShiftPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show a different page"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Widget kind") var kind: String
    @Parameter(title: "Pages") var delta: Int

    init() {}

    init(kind: String, delta: Int) {
        self.kind = kind
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        WidgetStore.shiftListPage(by: delta, for: kind)
        return .result()
    }
}

// MARK: - The buttons

/// The page's calendar navigation, at widget scale: previous, today, next.
///
/// Font Awesome rather than SF Symbols, because these three are the one place
/// the widget sits directly alongside the same controls on the page. The faces
/// are the Free build the app already bundles - see `FAIcon` for which glyphs
/// stand in for the Pro ones the page asks for.
struct DayNavBar: View {
    let kind: String
    var glyphSize: CGFloat = 11
    /// The "today" button is the one people reach for without looking, so it is
    /// allowed to be bigger than the two beside it.
    var centerGlyphSize: CGFloat? = nil
    var buttonSize: CGFloat = 20
    var spacing: CGFloat = 10
    /// Teal on a light background, like the page. On the day box's dark header
    /// it takes the lighter teal instead, which holds up against the grey.
    var tint: Color = .blankeePrimary

    var body: some View {
        HStack(spacing: spacing) {
            Button(intent: ShiftDayIntent(kind: kind, delta: -1)) {
                glyph(FAIcon.circleLeft, size: glyphSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            Button(intent: ShowTodayIntent(kind: kind)) {
                glyph(FAIcon.calendarDay, size: centerGlyphSize ?? glyphSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today")

            Button(intent: ShiftDayIntent(kind: kind, delta: 1)) {
                glyph(FAIcon.circleRight, size: glyphSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next day")
        }
    }

    private func glyph(_ icon: String, size: CGFloat) -> some View {
        Text(icon)
            .font(BlankeeFont.awesome(size))
            .foregroundStyle(tint)
            // A tap target the size of the icon would be unhittable. The frame
            // is the button; the glyph just sits in the middle of it.
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
    }
}
