//
//  Config.swift
//  blankee.app
//
//  Created by Camden Zupon on 12/27/25.
//

import Foundation

enum Environment {
    case production
    case goofdev     // goofdev environment
    case dev         // dev environment
    
    var baseURL: String {
        switch self {
        case .production:
            return "https://blankee.example.com"
        case .goofdev:
            return "http://192.0.2.45/"
        case .dev:
            return "http://192.0.2.44/"
        }
    }
    
    var displayName: String {
        switch self {
        case .production:
            return "Blankee"
        case .goofdev:
            return "Blankee (Goof Dev)"
        case .dev:
            return "Blankee (Dev)"
        }
    }
}

struct Config {
    // MARK: - Current Environment
    // Change this line to switch between environments:
    static let current: Environment = .goofdev
    
    // MARK: - Convenience Properties
    static var baseURL: String {
        current.baseURL
    }
    
    static var displayName: String {
        current.displayName
    }
    
    // MARK: - API Endpoints
    static var registerDeviceTokenURL: String {
        "\(baseURL)/api/notifications/register"
    }
    
    static var unreadNotificationCountURL: String {
        "\(baseURL)/get-unread-notification-count"
    }
}
