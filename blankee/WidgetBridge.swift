// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  WidgetBridge.swift
//  blankee.app
//
//  The app half of the home screen widget.
//
//  The widget runs in its own process and cannot see the web view's session, so
//  the app mints it a token - from inside that session, where it is the only
//  thing that can - and drops it in the shared app group. After that the widget
//  talks to the server on its own.
//

import Foundation
import UIKit
import WebKit
import WidgetKit

/// Main-actor bound throughout: everything here either reads a WKWebView or its
/// data store, and both are main-actor isolated.
@MainActor
enum WidgetBridge {

    /// Called when a page finishes loading in the web view.
    ///
    /// Two jobs, in this order: make sure the widget has a usable token, and
    /// then tell it to redraw. The redraw is the reason an edit made in the app
    /// appears on the home screen straight away instead of at the next tick of
    /// the widget's own timer.
    static func webViewDidFinishLoad(_ webView: WKWebView, serverURL: URL) {
        Task {
            await ensureToken(webView, serverURL: serverURL)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Points the widget at a different server, or at nothing.
    ///
    /// Revoking server-side first is the part that matters: clearing the local
    /// copy only stops this device asking, and a token that is merely forgotten
    /// is a token still live on the server.
    static func serverChanged(to newServer: URL?, previous: URL?) {
        Task {
            if let previous {
                await revokeToken(on: previous)
            }
            WidgetStore.clear()
            if let newServer {
                WidgetStore.serverURL = newServer
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The page just saved something, so the widget's figures are stale.
    ///
    /// Rate limited rather than passed straight through. WidgetKit gives each
    /// widget a daily reload budget and quietly starts ignoring requests past
    /// it, so someone typing down a column of amounts must not spend the whole
    /// day's allowance in a minute. The trailing reload matters as much as the
    /// limit: suppressing a burst and then never redrawing would leave exactly
    /// the stale widget this exists to prevent.
    private static var lastReload = Date.distantPast
    private static var pendingReload: Task<Void, Never>?
    private static let minimumGap: TimeInterval = 15

    static func dataDidChange() {
        pendingReload?.cancel()

        let waited = Date().timeIntervalSince(lastReload)
        guard waited < minimumGap else {
            reloadNow()
            return
        }

        let delay = minimumGap - waited
        pendingReload = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            reloadNow()
        }
    }

    private static func reloadNow() {
        lastReload = Date()
        pendingReload = nil
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 Data changed, widget timelines reloaded")
    }

    // MARK: - Token

    /// Mints a token if there is not already one for this server.
    ///
    /// Skipped entirely while the web view is sitting on the login page - the
    /// request would come back as a redirect, and asking on every load of a
    /// page nobody has signed in on yet is a lot of noise for nothing.
    private static func ensureToken(_ webView: WKWebView, serverURL: URL) async {
        if WidgetStore.serverURL != serverURL {
            // A different server than the one the token was issued by. The old
            // token means nothing here.
            WidgetStore.clear()
            WidgetStore.serverURL = serverURL
        }
        if let existing = WidgetStore.token {
            // A stored token is not proof of a working one: the server may have
            // dropped it since - an account reset, a rebuild, a revoke from
            // another device. Checked once per launch, not on every page, so
            // the ordinary case costs one request rather than one per load.
            guard !tokenCheckedThisLaunch else { return }
            tokenCheckedThisLaunch = true
            if await serverAccepts(existing, on: serverURL) { return }
            print("ℹ️ Stored widget token is no longer accepted by \(serverURL.host ?? "server"); requesting a new one")
            WidgetStore.token = nil
        }
        guard await isSignedIn(webView) else {
            print("ℹ️ Not signed in yet, so no widget token was requested")
            return
        }

        guard let url = URL(string: serverURL.absoluteString + "/api/widget-token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["label": deviceLabel])
        await attachWebViewCookies(to: &request, from: webView)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // 404 is a server older than this feature, not a failure to fix by
            // retrying. Remembered so the widget can say what is actually wrong.
            if status == 404 {
                WidgetStore.serverSupportsWidget = false
                print("⚠️ \(serverURL.host ?? "server") has no /api/widget-token - it predates the widget")
                return
            }

            guard status == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = body["token"] as? String else {
                print("⚠️ Widget token not issued (HTTP \(status)); will retry on the next load")
                return
            }

            WidgetStore.serverSupportsWidget = true
            WidgetStore.save(serverURL: serverURL, token: token)
            print("✅ Widget token stored for \(serverURL.host ?? "server")")
        } catch {
            print("⚠️ Widget token request failed: \(error.localizedDescription)")
        }
    }

    private static var tokenCheckedThisLaunch = false

    /// Asks the widget's own endpoint with the token and reads the answer the
    /// way the widget does: a 401/403, or a redirect that lands on the login
    /// page, means the server no longer knows this token. Anything else -
    /// including the server being unreachable - is not evidence against it.
    private static func serverAccepts(_ token: String, on serverURL: URL) async -> Bool {
        guard let url = URL(string: serverURL.absoluteString + "/api/widget/day-box") else { return true }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Blankee-Widget-Token")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return true }
        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 302 { return false }
        if response.url?.path.contains("login") == true { return false }
        return true
    }

    private static func revokeToken(on serverURL: URL) async {
        guard WidgetStore.token != nil,
              let url = URL(string: serverURL.absoluteString + "/api/widget-token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["label": deviceLabel])
        await attachWebViewCookies(to: &request, from: nil)

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Cookies

    /// Copies the web view's cookies onto a URLSession request.
    ///
    /// WKWebView keeps its cookies in its own WKHTTPCookieStore and does not
    /// populate HTTPCookieStorage.shared, so a request built the ordinary way
    /// arrives logged out. Reading them out explicitly is the only thing that
    /// works, and it is why this runs in the app rather than in the widget -
    /// the extension has no web view to read from.
    private static func attachWebViewCookies(to request: inout URLRequest, from webView: WKWebView?) async {
        let store = webView?.configuration.websiteDataStore ?? WKWebsiteDataStore.default()
        let cookies = await store.httpCookieStore.allCookies()

        guard let host = request.url?.host else { return }
        let relevant = cookies.filter { cookie in
            host == cookie.domain || host.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(host)
        }
        guard !relevant.isEmpty else { return }

        for (field, value) in HTTPCookie.requestHeaderFields(with: relevant) {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    /// Whether the web view is showing a signed-in page rather than the login
    /// screen. Judged by the presence of Flask-Login's cookies, because the URL
    /// alone does not say - the login page and the dashboard are both served
    /// from the same host.
    private static func isSignedIn(_ webView: WKWebView) async -> Bool {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return cookies.contains { $0.name == "session" || $0.name == "remember_token" }
    }

    /// Names the token in the server's list, so two devices are tellable apart
    /// and reinstalling replaces a row rather than adding one.
    private static var deviceLabel: String {
        UIDevice.current.name
    }
}
