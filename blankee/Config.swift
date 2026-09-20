// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  Config.swift
//  blankee.app
//
//  Created by Camden Zupon on 12/27/25.
//

import Foundation

/// Where the app points. Blankee is self-hosted, so the server is whatever the
/// user entered on the setup screen - see ServerSettings - rather than a
/// compile-time constant. Everything here is nil until they have entered one.
struct Config {
    static var serverURL: URL? {
        ServerSettings.shared.serverURL
    }
    
    static var baseURL: String? {
        serverURL?.absoluteString
    }
    
    static var displayName: String {
        "Blankee"
    }

    /// The push relay (see relay/README.md in the server's source). The one
    /// address in the app that is not the person's own server: Apple only
    /// accepts a push from the key of the account that signed the app, so a
    /// self-hosted server asks the relay, and the phone registers there too.
    static let pushRelayURL = URL(string: "https://push.blankee.io")!

    /// Which of Apple's two push environments this build's tokens belong to.
    /// A build from Xcode carries the development entitlement and gets a
    /// sandbox token; TestFlight and the App Store get production ones.
    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
    
    // MARK: - API Endpoints
    
    static var registerDeviceTokenURL: URL? {
        endpoint("/api/notifications/register")
    }
    
    static var unreadNotificationCountURL: URL? {
        endpoint("/get-unread-notification-count")
    }
    
    /// Appends a path to the configured server, keeping any sub-path the user
    /// typed: "https://example.com/blankee" + "/x" -> "https://example.com/blankee/x".
    static func endpoint(_ path: String) -> URL? {
        guard let serverURL else { return nil }
        return URL(string: serverURL.absoluteString + path)
    }
}
