// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  NotificationService.swift
//  NotificationServiceExtension
//
//  Runs on every push before it is shown, and does one of two things.
//
//  A push from a server that talks to Apple directly carries its text, as
//  HTML from the notification's message; that is stripped to plain text, as
//  it always was.
//
//  A push from the relay carries no text at all - only the notification's id
//  (`nid`), or `kind: reminder` for the evening nudge, which has no row. The
//  relay is not trusted with what a notification says. So the text is fetched
//  here, from the person's own server, with the widget token the app minted
//  and left in the shared app group; then the alert is filled in, the link
//  the app opens on a tap is attached, and the badge set from the unread
//  count. If the server cannot be reached in time the alert goes out with
//  the relay's generic text and a tap opens the notifications list.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        content.body = stripHTML(from: content.body)

        let userInfo = content.userInfo
        let id = (userInfo["nid"] as? Int) ?? Int((userInfo["nid"] as? String) ?? "") ?? 0
        let kind = userInfo["kind"] as? String

        if kind == "reminder" {
            // The evening reminder: no row to fetch, and the app knows what
            // to do with it - the same action the direct push carries.
            content.body = "Entries are waiting to be confirmed, and your balance to check."
            content.userInfo["action"] = "bucket_prompt"
            contentHandler(content)
            return
        }

        guard id > 0 else {
            // Not from the relay: the text came with the push.
            contentHandler(content)
            return
        }

        content.userInfo["url"] = "/notifications"
        Task {
            do {
                let detail = try await WidgetAPI.fetch(NotificationDetail.self,
                                                       path: "/api/widget/notification",
                                                       query: [URLQueryItem(name: "id", value: String(id))],
                                                       definesSupport: false)
                content.body = detail.message
                content.userInfo["url"] = detail.url
                content.badge = NSNumber(value: detail.unreadCount)
            } catch {
                print("⚠️ Could not fetch notification \(id) for the alert: \(error)")
            }
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - HTML Stripping

    private func stripHTML(from string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result
    }
}

/// What /api/widget/notification answers.
struct NotificationDetail: Decodable {
    let id: Int
    let message: String
    let url: String
    let unreadCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, message, url
        case unreadCount = "unread_count"
    }
}
