//
//  blankeeApp.swift
//  blankee.app
//
//  Created by blankee.io on 10/26/25.
//

import SwiftUI
import UserNotifications

@main
struct blankee_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permission on app launch
        NotificationManager.shared.requestAuthorization()
        
        return true
    }
    
    // MARK: - Push Notification Handlers
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.handleDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Strip HTML from notification body before presenting
        let originalBody = notification.request.content.body
        let cleanBody = NotificationManager.shared.stripHTMLPublic(from: originalBody)
        
        print("📨 Intercepted notification before display")
        print("   Original body: \(originalBody)")
        print("   Clean body: \(cleanBody)")
        
        // If the body has HTML, create a new notification with clean text
        if cleanBody != originalBody {
            let content = UNMutableNotificationContent()
            content.title = notification.request.content.title
            content.body = cleanBody
            content.sound = notification.request.content.sound
            content.badge = notification.request.content.badge
            content.userInfo = notification.request.content.userInfo
            
            let request = UNNotificationRequest(
                identifier: notification.request.identifier + "-cleaned",
                content: content,
                trigger: nil
            )
            
            center.add(request) { error in
                if let error = error {
                    print("❌ Error adding cleaned notification: \(error)")
                } else {
                    print("✅ Replaced HTML notification with clean version")
                }
            }
            
            // Don't show the original (with HTML)
            completionHandler([])
        } else {
            // No HTML detected, show normally
            print("✅ No HTML detected, showing notification normally")
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationManager.shared.handleNotificationReceived(response.notification)
        completionHandler()
    }
}
