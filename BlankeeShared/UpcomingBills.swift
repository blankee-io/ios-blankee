// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  UpcomingBills.swift
//  blankee.app
//
//  The Summary page's Upcoming Bills, as the widget reads them from
//  /api/widget/upcoming-bills: every recurring bill and bucket - the budget's
//  and each card's - with its last occurrence and the one coming up, in the
//  page's order (the person's pinned bills first, then soonest first).
//
//  The widget filters the rows itself, with the same three questions as the
//  page's filter: paid from the budget or a card, a bill or a bucket, and
//  unpaid or paid this month.
//

import Foundation

struct BillSide: Decodable {
    /// YYYY-MM-DD.
    let date: String?
    let originalAmount: Double
    /// What is left: 0 on a paid bill, the remainder of a bucket.
    let currentAmount: Double
    let paid: Bool

    private enum CodingKeys: String, CodingKey {
        case date, paid
        case originalAmount = "original_amount"
        case currentAmount = "current_amount"
    }
}

struct BillRow: Decodable, Identifiable {
    /// 'e:<id>' for the budget's, 'c:<id>' for a card's.
    let key: String
    let name: String
    /// The card's name, on a card's row.
    let accountName: String?
    /// A bill is paid in one go; a bucket is spent down.
    let isBill: Bool
    let pinned: Bool
    let last: BillSide?
    let upcoming: BillSide?
    let paidThisMonth: Bool
    let dueThisMonth: Bool

    var id: String { key }
    var isCard: Bool { key.hasPrefix("c:") }

    private enum CodingKeys: String, CodingKey {
        case key, name, pinned, last, upcoming
        case accountName = "account_name"
        case isBill = "is_bill"
        case paidThisMonth = "paid_this_month"
        case dueThisMonth = "due_this_month"
    }
}

struct BillsAsOf: Decodable {
    let date: String
    /// "Oct 15", with the year when it is not this one.
    let label: String
}

struct UpcomingBills: Decodable {
    let currencySymbol: String
    /// The last bank sync, as the page's header shows it. Nil with nothing linked.
    let asOf: BillsAsOf?
    let rows: [BillRow]
    let dataVersion: String

    private enum CodingKeys: String, CodingKey {
        case rows
        case currencySymbol = "currency_symbol"
        case asOf = "as_of"
        case dataVersion = "data_version"
    }

    init(currencySymbol: String, asOf: BillsAsOf?, rows: [BillRow], dataVersion: String) {
        self.currencySymbol = currencySymbol
        self.asOf = asOf
        self.rows = rows
        self.dataVersion = dataVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currencySymbol = try c.decodeIfPresent(String.self, forKey: .currencySymbol) ?? "$"
        asOf = try c.decodeIfPresent(BillsAsOf.self, forKey: .asOf)
        rows = try c.decodeIfPresent([BillRow].self, forKey: .rows) ?? []
        // A number or a string, as in Trends.
        if let text = try? c.decode(String.self, forKey: .dataVersion) {
            dataVersion = text
        } else if let number = try? c.decode(Int.self, forKey: .dataVersion) {
            dataVersion = String(number)
        } else {
            dataVersion = "0"
        }
    }

    /// "$1,200.00".
    func format(_ value: Double) -> String {
        Trends.full(value, symbol: currencySymbol)
    }
}

// MARK: - The filter

/// The page's three filter questions. Each widget button steps through its
/// answers, "all" first, and comes back round.
enum BillFilter {

    enum Question: String, CaseIterable {
        case source, kind, status
    }

    struct Selection {
        var source: String = "all"   // all, budget, card
        var kind: String = "all"     // all, bill, bucket
        var status: String = "all"   // all, unpaid, paid

        func value(_ question: Question) -> String {
            switch question {
            case .source: return source
            case .kind: return kind
            case .status: return status
            }
        }

        /// The same rule as the page's billMatches(). Buckets are neither paid
        /// nor unpaid, so either of those shows bills only.
        func matches(_ row: BillRow) -> Bool {
            if source == "budget" && row.isCard { return false }
            if source == "card" && !row.isCard { return false }
            if kind == "bill" && !row.isBill { return false }
            if kind == "bucket" && row.isBill { return false }
            if status == "unpaid" && !row.dueThisMonth { return false }
            if status == "paid" && !row.paidThisMonth { return false }
            return true
        }

        var isFiltering: Bool { source != "all" || kind != "all" || status != "all" }
    }

    static func answers(_ question: Question) -> [String] {
        switch question {
        case .source: return ["all", "budget", "card"]
        case .kind: return ["all", "bill", "bucket"]
        case .status: return ["all", "unpaid", "paid"]
        }
    }

    /// What the button says for each answer - "all" spelled out, so a button
    /// never reads as a choice it is not.
    static func label(_ question: Question, _ value: String) -> String {
        switch (question, value) {
        case (.source, "budget"): return "Budget"
        case (.source, "card"): return "Cards"
        case (.source, _): return "Budget & cards"
        case (.kind, "bill"): return "Bills"
        case (.kind, "bucket"): return "Buckets"
        case (.kind, _): return "Bills & buckets"
        case (.status, "unpaid"): return "Unpaid"
        case (.status, "paid"): return "Paid"
        case (.status, _): return "Paid & unpaid"
        }
    }

    static func selection(for kind: String) -> Selection {
        var s = Selection()
        for question in Question.allCases {
            let stored = WidgetStore.filterValue(question.rawValue, for: kind)
            let value = answers(question).contains(stored ?? "") ? stored! : "all"
            switch question {
            case .source: s.source = value
            case .kind: s.kind = value
            case .status: s.status = value
            }
        }
        return s
    }

    /// The next answer to one question, wrapping back to "all".
    static func advance(_ question: Question, for kind: String) {
        let list = answers(question)
        let current = selection(for: kind).value(question)
        let next = list[((list.firstIndex(of: current) ?? 0) + 1) % list.count]
        WidgetStore.setFilterValue(next == "all" ? nil : next, question.rawValue, for: kind)
    }
}

// MARK: - Fetching

enum UpcomingBillsService {
    static func fetch() async throws -> UpcomingBills {
        try await WidgetAPI.fetch(UpcomingBills.self, path: "/api/widget/upcoming-bills", definesSupport: false)
    }
}
