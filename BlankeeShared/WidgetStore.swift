// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  WidgetStore.swift
//  blankee.app
//
//  What the app and the widget have to agree on.
//
//  A WidgetKit extension is a separate process with its own container, so it
//  can see neither UserDefaults.standard nor the web view's cookies. Everything
//  it needs - which server, and a token to read it with - is written here by
//  the app and read back by the widget.
//

import Foundation

/// The app group both targets are members of. Must match the App Groups
/// capability on the app target *and* on the widget extension target, or the
/// suite silently falls back to standard defaults and the widget never sees a
/// token.
let blankeeAppGroup = "group.io.blankee.blankee"

/// The URL the widget hands back to the system when someone taps it. The app
/// registers this scheme in its Info.plist and answers it in ContentView.
let blankeeDayBoxDeepLink = URL(string: "blankee://dashboard_d")!

/// Where the trend widget goes: the summary page its graphs come from.
let blankeeSummaryDeepLink = URL(string: "blankee://dashboard_summary")!

/// Server address and widget token, shared across the group container.
///
/// The token is a bearer credential, so it lives in the group's keychain rather
/// than in its defaults - defaults are a plist in a directory that is backed up
/// and restorable, and a token that outlives the device it was issued to is a
/// token nobody can account for.
enum WidgetStore {

    private static let serverKey = "widget.serverURL"
    private static let supportedKey = "widget.serverSupportsWidget"
    private static let keychainAccount = "widget.token"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: blankeeAppGroup)
    }

    // MARK: - Server

    static var serverURL: URL? {
        get {
            guard let stored = defaults?.string(forKey: serverKey) else { return nil }
            return URL(string: stored)
        }
        set {
            if let newValue {
                defaults?.set(newValue.absoluteString, forKey: serverKey)
            } else {
                defaults?.removeObject(forKey: serverKey)
            }
        }
    }

    /// Whether the configured server has the widget endpoints at all. Nil until
    /// the app has asked once.
    static var serverSupportsWidget: Bool? {
        get { defaults?.object(forKey: supportedKey) as? Bool }
        set {
            if let newValue {
                defaults?.set(newValue, forKey: supportedKey)
            } else {
                defaults?.removeObject(forKey: supportedKey)
            }
        }
    }

    // MARK: - Token

    static var token: String? {
        get { readSecret(account: keychainAccount) }
        set { writeSecret(newValue, account: keychainAccount) }
    }

    /// The secret the app made up for the push relay and gave to both the
    /// relay and the server. Kept here, in the group keychain, for the same
    /// reasons as the token, and so a reinstall that keeps the group data
    /// keeps its identity with the relay.
    static var relaySecret: String? {
        get { readSecret(account: "relay.secret") }
        set { writeSecret(newValue, account: "relay.secret") }
    }

    private static func readSecret(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeSecret(_ value: String?, account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ \(account) not saved to the keychain: OSStatus \(status)")
        }
    }

    private static var baseQuery: [String: Any] { baseQuery(account: keychainAccount) }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.blankee.widget",
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: blankeeAppGroup,
        ]
    }

    // MARK: - Which day is on screen

    /// How many days from today a widget is showing, keyed by widget kind so the
    /// medium and small ones page independently.
    ///
    /// Anchored to the day it was set on. A widget left showing "two days ahead"
    /// would otherwise keep sliding forward every midnight, and nobody who set
    /// it three weeks ago would remember why it is pointing where it is - so the
    /// offset lapses when the date turns over and the widget comes home to
    /// today.
    static func dayOffset(for kind: String) -> Int {
        guard let defaults,
              defaults.string(forKey: anchorKey(kind)) == todayStamp else { return 0 }
        return defaults.integer(forKey: offsetKey(kind))
    }

    static func setDayOffset(_ offset: Int, for kind: String) {
        defaults?.set(offset, forKey: offsetKey(kind))
        defaults?.set(todayStamp, forKey: anchorKey(kind))
    }

    static func shiftDayOffset(by delta: Int, for kind: String) {
        setDayOffset(dayOffset(for: kind) + delta, for: kind)
    }

    /// Which page of a list a widget is showing. Not anchored to a date the
    /// way the day offset is - the provider clamps it against however many
    /// pages there actually are, so a stale value corrects itself on the next
    /// load rather than needing to expire.
    static func listPage(for kind: String) -> Int {
        defaults?.integer(forKey: pageKey(kind)) ?? 0
    }

    static func setListPage(_ page: Int, for kind: String) {
        defaults?.set(page, forKey: pageKey(kind))
    }

    static func shiftListPage(by delta: Int, for kind: String) {
        setListPage(listPage(for: kind) + delta, for: kind)
    }

    private static func pageKey(_ kind: String) -> String { "widget.listPage.\(kind)" }

    private static func offsetKey(_ kind: String) -> String { "widget.dayOffset.\(kind)" }
    private static func anchorKey(_ kind: String) -> String { "widget.dayAnchor.\(kind)" }

    private static var todayStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Lifecycle

    /// True when the widget has everything it needs to ask for data.
    static var isConfigured: Bool {
        serverURL != nil && token != nil
    }

    static func save(serverURL url: URL, token newToken: String) {
        serverURL = url
        token = newToken
    }

    /// Signing out, or pointing the app at a different server, invalidates
    /// everything here. Called alongside the server-side revoke, not instead of
    /// it - this only stops the widget asking, it does not stop the token
    /// working if a copy of it exists elsewhere.
    static func clear() {
        serverURL = nil
        token = nil
        serverSupportsWidget = nil
    }
}
