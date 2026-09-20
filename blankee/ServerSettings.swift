// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  ServerSettings.swift
//  blankee.app
//
//  Remembers which self-hosted Blankee server the app points at.
//

import Foundation
import Combine

// MARK: - Stored Server

class ServerSettings: ObservableObject {
    static let shared = ServerSettings()
    
    private static let storageKey = "serverURL"
    
    /// The server the web view loads. `nil` until the user has entered one,
    /// which is what puts the setup screen on screen at first launch.
    @Published private(set) var serverURL: URL?
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: ServerSettings.storageKey) {
            self.serverURL = URL(string: stored)
        }
    }
    
    var isConfigured: Bool {
        serverURL != nil
    }
    
    func save(_ url: URL) {
        defaults.set(url.absoluteString, forKey: ServerSettings.storageKey)
        serverURL = url
    }
    
    func forget() {
        defaults.removeObject(forKey: ServerSettings.storageKey)
        serverURL = nil
    }
}

// MARK: - Address Parsing

/// Turns what somebody types - "192.168.1.50:18420", "blankee.local",
/// "https://budget.example.com/app" - into a URL the web view can load.
enum ServerAddress {
    
    enum ValidationError: LocalizedError, Equatable {
        case empty
        case malformed
        case unsupportedScheme(String)
        case insecureRemoteHost(String)
        
        var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter the address of your Blankee server."
            case .malformed:
                return "That does not look like an address. Try 192.168.1.50:18420 or blankee.example.com."
            case .unsupportedScheme(let scheme):
                return "\(scheme):// is not supported. Use http:// or https://."
            case .insecureRemoteHost(let host):
                return "iOS blocks plain http:// to \(host), because it is outside your local network. Use https:// instead."
            }
        }
    }
    
    /// Normalizes user input into a loadable URL, or throws a message worth showing.
    static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ValidationError.empty }
        
        if !text.contains("://") {
            // No scheme typed: http on the local network, where certificates are
            // rare, and https everywhere else, which is what iOS will allow anyway.
            let authority = String(text.split(separator: "/").first ?? "")
            text = (isLocalNetworkHost(hostOnly(authority)) ? "http://" : "https://") + text
        }
        
        guard var components = URLComponents(string: text),
              let host = components.host,
              !host.isEmpty else {
            throw ValidationError.malformed
        }
        
        let scheme = (components.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw ValidationError.unsupportedScheme(scheme.isEmpty ? "that" : scheme)
        }
        // Caught here rather than as a blank web view later: App Transport
        // Security permits plain http only for the local network.
        if scheme == "http" && !isLocalNetworkHost(host) {
            throw ValidationError.insecureRemoteHost(host)
        }
        
        components.scheme = scheme
        // Keep a real sub-path, drop a trailing slash and anything after it.
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        
        guard let url = components.url else { throw ValidationError.malformed }
        return url
    }
    
    /// Whether iOS will treat this host as local, and so allow plain http to it.
    /// Mirrors what NSAllowsLocalNetworking in Info.plist actually permits.
    static func isLocalNetworkHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
            return true
        }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fd") {
            return true
        }
        
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
            let octets = parts.compactMap { UInt8($0) }
            switch (octets[0], octets[1]) {
            case (127, _), (10, _):
                return true
            case (192, 168), (169, 254):
                return true
            case (172, 16...31):
                return true
            default:
                return false
            }
        }
        
        // A single-label name - "nas", "blankee" - can only be on the local network.
        return !host.contains(".")
    }
    
    private static func hostOnly(_ authority: String) -> String {
        var host = authority
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            return String(host[host.index(after: host.startIndex)..<close]).lowercased()
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        return host.lowercased()
    }
    
    // MARK: - Reachability
    
    struct ProbeResult {
        let reachable: Bool
        /// Why it failed, phrased for the person who typed the address.
        let detail: String?
    }
    
    /// Asks the server for its front page so a typo is caught during setup
    /// rather than as a blank screen. Any HTTP answer counts as reachable -
    /// a login redirect or a 401 still means the server is there.
    static func probe(_ url: URL) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ProbeResult(reachable: false, detail: "The server did not answer with HTTP.")
            }
            if http.statusCode >= 500 {
                return ProbeResult(reachable: false, detail: "The server answered with HTTP \(http.statusCode).")
            }
            return ProbeResult(reachable: true, detail: nil)
        } catch {
            return ProbeResult(reachable: false, detail: error.localizedDescription)
        }
    }
}
