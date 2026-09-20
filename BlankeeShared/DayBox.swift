// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  DayBox.swift
//  blankee.app
//
//  One day's box from /api/widget/day-box, which is the same day container
//  dashboard_d.html draws. Every figure is computed on the server so the widget
//  and the page cannot disagree about what a day added up to.
//

import Foundation

// MARK: - Model

struct DayBox: Codable, Equatable {

    struct Line: Codable, Equatable, Identifiable {
        let categoryName: String
        let amount: Double
        /// One of the icon names in `DayBoxIcon`. The server picks it with the
        /// same branch order the page uses.
        let icon: String
        let isPending: Bool
        let isPaid: Bool
        let isBucket: Bool

        /// Stable enough for a list that is rebuilt on every timeline entry.
        var id: String { "\(categoryName)-\(amount)" }

        enum CodingKeys: String, CodingKey {
            case categoryName = "category_name"
            case amount
            case icon
            case isPending = "is_pending"
            case isPaid = "is_paid"
            case isBucket = "is_bucket"
        }
    }

    struct CreditAccount: Codable, Equatable {
        let name: String
        let mask: String
        let entries: [Line]
        let balance: Double
    }

    enum RemainderState: String, Codable {
        case negative
        case belowThreshold = "below_threshold"
        case aboveThreshold = "above_threshold"
        /// Before the user joined, where the page dims the box instead of
        /// colouring the remainder.
        case neutral
    }

    let date: String
    let dateLabel: String
    let currencySymbol: String
    let lastRemainder: Double
    let income: [Line]
    let totalIncome: Double
    let expenses: [Line]
    let totalExpenses: Double
    let remainder: Double
    let remainderState: RemainderState
    let creditAccounts: [CreditAccount]
    let savings: Double
    let isBeforeMemberSince: Bool
    let dataVersion: String

    enum CodingKeys: String, CodingKey {
        case date
        case dateLabel = "date_label"
        case currencySymbol = "currency_symbol"
        case lastRemainder = "last_remainder"
        case income
        case totalIncome = "total_income"
        case expenses
        case totalExpenses = "total_expenses"
        case remainder
        case remainderState = "remainder_state"
        case creditAccounts = "credit_accounts"
        case savings
        case isBeforeMemberSince = "is_before_member_since"
        case dataVersion = "data_version"
    }

    /// Formats a figure the way the web app's formatCurrency does - symbol
    /// first, en-US grouping, always two decimals. A negative therefore reads
    /// "$-45.00", which looks odd written down and is exactly what the page
    /// shows, so it is what the widget shows too.
    func format(_ value: Double) -> String {
        currencySymbol + DayBox.groupedFormatter.string(from: NSNumber(value: value))!
    }

    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

// MARK: - Fetching

enum DayBoxError: LocalizedError {
    case notConfigured
    /// The server is reachable and the person is signed in, but it predates the
    /// widget endpoints. Worth its own case: everything looks correct from the
    /// device, and telling someone to sign in when they already have is the
    /// least useful thing a widget can say.
    case serverTooOld
    case unauthorized
    case server(Int)
    case transport(String)
    /// A 200 that will not decode. Almost always the login page, arriving with
    /// a 200 because URLSession followed the redirect for us.
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Open Blankee and sign in."
        case .serverTooOld:
            return "Your Blankee server needs updating."
        case .unauthorized:
            return "Sign in to Blankee again."
        case .server(let code):
            return "Server error \(code)."
        case .transport:
            return "Can't reach your server."
        case .badResponse:
            return "Your server sent something unexpected."
        }
    }
}

enum DayBoxService {

    /// Asks the server for a day's box.
    ///
    /// The date is the *device's* date rather than the server's. A phone in a
    /// timezone behind its server would otherwise be shown tomorrow's box,
    /// which is the one bug in a widget like this that nobody would report and
    /// everybody would notice.
    static func fetch(for day: Date = Date()) async throws -> DayBox {
        try await WidgetAPI.fetch(DayBox.self, path: "/api/widget/day-box",
                                  query: [URLQueryItem(name: "date", value: WidgetAPI.isoDay.string(from: day))])
    }
}

/// One GET against the widget endpoints, with the token, the status mapping and
/// the login-page detection every widget needs. The day box and the trend graph
/// differ only in path and payload, so they share this rather than each
/// carrying its own copy of what "signed out" looks like on the wire.
enum WidgetAPI {

    /// `definesSupport` says whether a 404 here means the server predates
    /// widgets altogether. True for the day box, the first endpoint a server
    /// ever had; false for later ones, where a 404 only means *this* widget is
    /// newer than the server and the others should keep working.
    static func fetch<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = [],
                                    definesSupport: Bool = true) async throws -> T {
        guard let base = WidgetStore.serverURL else { throw DayBoxError.notConfigured }
        if WidgetStore.serverSupportsWidget == false { throw DayBoxError.serverTooOld }
        guard let token = WidgetStore.token else { throw DayBoxError.notConfigured }

        var components = URLComponents(string: base.absoluteString + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw DayBoxError.notConfigured }

        var request = URLRequest(url: url)
        // Its own header, not Authorization: mod_wsgi strips Authorization
        // unless the vhost opts in with WSGIPassAuthorization On, and Apache +
        // mod_wsgi is how install.sh deploys the server. Both are sent - the
        // server accepts either - so a deployment that passes Authorization
        // through keeps working too.
        request.setValue(token, forHTTPHeaderField: "X-Blankee-Widget-Token")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // A widget showing yesterday's figures is worse than one showing a
        // spinner, and URLSession will happily serve a cached body otherwise.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DayBoxError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            // 302 is the login redirect: the token has been revoked, or the
            // server was rebuilt without it.
            if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 302 {
                throw rejected()
            }
            if http.statusCode == 404 {
                if definesSupport { WidgetStore.serverSupportsWidget = false }
                throw DayBoxError.serverTooOld
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DayBoxError.server(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Landing on /login means the token was rejected. Anything else
            // that will not decode is a real mismatch, and calling that
            // "signed out" sends people to re-enter a password that was never
            // the problem.
            if response.url?.path.contains("login") == true {
                throw rejected()
            }
            throw DayBoxError.badResponse
        }
    }

    /// The server has said no to the token, so it is forgotten here as well.
    ///
    /// Keeping it would leave the widget stuck: the app only mints a token when
    /// there is none stored, so a token the server has dropped - the account
    /// was reset, the server was rebuilt, the row was revoked from another
    /// device - would be presented forever and refused forever. Dropping it is
    /// what makes the next launch of the app ask for a fresh one.
    private static func rejected() -> DayBoxError {
        WidgetStore.token = nil
        return .unauthorized
    }

    /// The device's local calendar day, matching the page's
    /// toLocaleDateString('en-CA').
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
