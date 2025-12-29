//
//  NotificationManager.swift
//  blankee.app
//
//  Created by Camden Zupon on 10/26/25.
//

import Foundation
import UserNotifications
import UIKit

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
        
        // Send to backend
        sendTokenToBackend(token)
    }
    
    private func sendTokenToBackend(_ token: String) {
        // TODO: Update this URL to match your backend's actual endpoint
        guard let url = URL(string: "https://blankee.example.com/api/notifications/register") else {
            print("Invalid backend URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication headers if required by your backend
        // request.setValue("Bearer YOUR_API_KEY", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "deviceToken": token,
            "platform": "ios",
            "deviceInfo": [
                "model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Failed to send token to backend: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                        print("✅ Device token successfully registered with backend")
                    } else {
                        print("⚠️ Token registration response: \(httpResponse.statusCode)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("Response body: \(responseString)")
                        }
                    }
                }
            }.resume()
        } catch {
            print("❌ Failed to serialize token data: \(error.localizedDescription)")
        }
    }
    
    func handleNotificationReceived(_ notification: UNNotification) {
        print("Notification received: \(notification.request.content.userInfo)")
        
        // Extract notification data
        let userInfo = notification.request.content.userInfo
        let title = notification.request.content.title
        let body = notification.request.content.body
        
        print("📬 Notification Details:")
        print("  Title: \(title)")
        print("  Body: \(body)")
        print("  Data: \(userInfo)")
        
        // TODO: Handle custom notification actions or deep linking
        // For example, if the notification contains a URL to open:
        // if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
        //     // Navigate to specific screen in webview
        // }
    }
    
    // Optional: Manually re-send token (useful for debugging or when user logs in)
    func resendDeviceToken() {
        if let token = UserDefaults.standard.string(forKey: "deviceToken") {
            print("🔄 Resending device token to backend...")
            sendTokenToBackend(token)
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
