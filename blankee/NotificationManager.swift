// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  NotificationManager.swift
//  blankee.app
//
//  Created by Camden Zupon on 10/26/25.
//

import Foundation
import UserNotifications
import UIKit
import WebKit

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device Token: \(token)")
        
        // Save locally
        UserDefaults.standard.set(token, forKey: "deviceToken")
        
        // The relay first, then the server: the server's push asks the relay
        // for this token, and the relay has to know it.
        Task {
            await registerWithRelay(token)
            await sendTokenToBackend(token)
        }
    }

    /// The secret shared with the relay and the server. Made once and kept in
    /// the group keychain; a phone that has lost it (a reinstall that wiped
    /// the group) makes a new one, and re-registering replaces the old.
    private var relaySecret: String {
        if let existing = WidgetStore.relaySecret { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        WidgetStore.relaySecret = secret
        return secret
    }

    /// Tells the relay this token exists and which secret goes with it. No
    /// session needed - the relay knows nothing about accounts - so it can
    /// happen the moment the token arrives.
    private func registerWithRelay(_ token: String) async {
        var request = URLRequest(url: Config.pushRelayURL.appendingPathComponent("v1/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "token": token,
            "secret": relaySecret,
            "environment": Config.pushEnvironment,
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print(status == 204 ? "✅ Registered with the push relay" : "⚠️ Push relay answered \(status)")
        } catch {
            print("⚠️ Could not reach the push relay: \(error.localizedDescription)")
        }
    }

    /// The token and server the backend last confirmed, so a page load does
    /// not re-register on every navigation - only when something changed, or
    /// when nothing has been confirmed yet.
    private var registeredToken: String?
    private var registeredServer: URL?

    /// Called when a page has loaded in the web view - the one moment it is
    /// known whether someone is signed in.
    ///
    /// Registration needs a session: the server's register route is behind
    /// login, and the token usually arrives at launch, before the web view has
    /// signed anyone in. So the token is sent with the web view's own cookies,
    /// and sent again here until the server has said yes. Without this, a
    /// token that arrived on the login screen was posted once, bounced to
    /// /login, and never tried again - which is why no device had ever been
    /// registered on any server.
    func ensureRegistered() {
        guard let server = Config.serverURL else { return }
        guard let token = UserDefaults.standard.string(forKey: "deviceToken") else {
            // Authorised but never handed a token - iOS asks Apple again on
            // request, and the token comes back through handleDeviceToken.
            if isAuthorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        guard registeredToken != token || registeredServer != server else { return }
        Task { await sendTokenToBackend(token) }
    }
    
    @MainActor
    private func sendTokenToBackend(_ token: String) async {
        guard let server = Config.serverURL, let url = Config.registerDeviceTokenURL else {
            print("No server configured yet - the token is saved and sent once there is one")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // The web view keeps its cookies in its own store, not in the one
        // URLSession reads, so a request built the ordinary way arrives signed
        // out. Copying them across is what makes the route's login check pass.
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        if let host = url.host {
            let relevant = cookies.filter { cookie in
                host == cookie.domain || host.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(host)
            }
            for (field, value) in HTTPCookie.requestHeaderFields(with: relevant) {
                request.setValue(value, forHTTPHeaderField: field)
            }
            if relevant.isEmpty {
                print("ℹ️ No session cookies yet; the device token will be sent once someone signs in")
                return
            }
        }
        
        let body: [String: Any] = [
            "deviceToken": token,
            "platform": "ios",
            // What the relay was told too, so the server can ask it for a
            // push to this phone and nobody else can.
            "relaySecret": relaySecret,
            "environment": Config.pushEnvironment,
            "deviceInfo": [
                "model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            // A redirect to the login page comes back as a 200 for that page,
            // because URLSession followed it. That is "not signed in", not
            // "registered".
            if response.url?.path.contains("login") == true || http.statusCode == 401 || http.statusCode == 403 {
                print("ℹ️ Device token not registered: not signed in yet; will retry after sign-in")
                return
            }
            if http.statusCode == 200 || http.statusCode == 201 {
                registeredToken = token
                registeredServer = server
                print("✅ Device token registered with \(server.host ?? "server")")
            } else {
                print("⚠️ Token registration response: \(http.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response body: \(responseString.prefix(300))")
                }
            }
        } catch {
            print("❌ Failed to send token to backend: \(error.localizedDescription)")
        }
    }
    
    /// The page a tapped notification should open, when the tap arrived
    /// before the web view existed - the app was closed and the notification
    /// is what launched it. The web view reads and clears this as it starts,
    /// so the first page shown is the one the alert was about rather than the
    /// landing page followed by a jump.
    var pendingWebPath: String?

    /// Somebody tapped a notification.
    ///
    /// The server sends one of two custom keys with an alert. `url` is the
    /// relative path of the page the notification's own link points at - the
    /// summary for a shortfall, the notifications list when there is no link.
    /// `action` is the evening reminder's, and names no page: the prompt it
    /// refers to is raised by the dashboard itself, so any dashboard will do
    /// and "/" lets the server pick the person's landing page.
    func handleNotificationReceived(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        print("📬 Notification tapped: \(userInfo)")

        guard let path = Self.webPath(for: userInfo) else { return }
        pendingWebPath = path
        NotificationCenter.default.post(name: .openWebPath, object: path)
    }

    /// Only a relative path is ever opened. The server already refuses to send
    /// anything else, and the same rule here means a payload from anywhere
    /// other than the server cannot point the web view off the site.
    static func webPath(for userInfo: [AnyHashable: Any]) -> String? {
        if let url = userInfo["url"] as? String, url.hasPrefix("/"), !url.hasPrefix("//") {
            return url
        }
        if userInfo["action"] as? String != nil {
            return "/"
        }
        return nil
    }
    
    // Optional: Manually re-send token (useful for debugging or when user logs in)
    func resendDeviceToken() {
        // A different server has never heard of this device, whatever the
        // last one said.
        registeredToken = nil
        registeredServer = nil
        if let token = UserDefaults.standard.string(forKey: "deviceToken") {
            print("🔄 Resending device token to backend...")
            Task { await sendTokenToBackend(token) }
        } else {
            print("⚠️ No device token found to resend")
        }
    }
    
    // Optional: Get current device token
    func getDeviceToken() -> String? {
        return UserDefaults.standard.string(forKey: "deviceToken")
    }
    
    // MARK: - Helper Functions
    
    /// Strip HTML tags from notification text (public version for AppDelegate)
    func stripHTMLPublic(from string: String) -> String {
        var result = string
        
        // Remove HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        
        // Decode HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        
        // Remove extra whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression,
            range: nil
        )
        
        return result
    }
    
    // MARK: - Badge Management
    
    /// Update the app badge count (red dot on app icon)
    func updateBadge(count: Int) {
        print("📛 Updating badge to: \(count)")
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error = error {
                    print("❌ Failed to update badge: \(error.localizedDescription)")
                } else {
                    print("✅ Badge updated to: \(count)")
                }
            }
        }
    }
    
    /// Clear the app badge
    func clearBadge() {
        updateBadge(count: 0)
    }
    
    // MARK: - Local Notifications
    
    /// Show a local notification
    func showLocalNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        print("📬 Attempting to show local notification: \(title) - \(body)")
        
        // Check if we have permission first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("⚠️ Notifications not authorized. Current status: \(settings.authorizationStatus.rawValue)")
                // Request permission if not yet determined
                if settings.authorizationStatus == .notDetermined {
                    self.requestAuthorization()
                }
                return
            }
            
            print("✅ Notification permission granted, creating notification...")
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = userInfo
            
            // Create a unique identifier
            let identifier = UUID().uuidString
            
            // Trigger immediately (0.1 seconds from now)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            
            // Create the request
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            // Add the notification to the center
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Error showing local notification: \(error.localizedDescription)")
                } else {
                    print("✅ Local notification scheduled: \(title) - \(body)")
                }
            }
        }
    }
}
