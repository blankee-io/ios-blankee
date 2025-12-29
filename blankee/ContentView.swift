//
//  ContentView.swift
//  blankee.app
//
//  Created by Camden Zupon on 10/26/25.
//

import SwiftUI

struct ContentView: View {
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var webViewKey = UUID()
    
    var webURL: URL {
        URL(string: Config.baseURL)!
    }
    
    var body: some View {
        ZStack {
            // Background color that extends into status bar area
            // Blankee header color: #2AAAA8
            Color(red: 42/255, green: 170/255, blue: 168/255)
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 0) {
                // Loading indicator
                if isLoading {
                    ProgressView()
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
                
                // WebView with pull-to-refresh
                RefreshableWebView(
                    url: webURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    webViewKey: $webViewKey
                )
                
                // MARK: - NAVIGATION TOOLBAR COMMENTED OUT
                // Uncomment the section below to re-enable the navigation toolbar
                /*
                // Navigation controls
                NavigationToolbar(
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    onBack: {
                        NotificationCenter.default.post(name: .webViewGoBack, object: nil)
                    },
                    onForward: {
                        NotificationCenter.default.post(name: .webViewGoForward, object: nil)
                    },
                    onRefresh: {
                        NotificationCenter.default.post(name: .webViewReload, object: nil)
                    }
                )
                */
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
}

// MARK: - Refreshable WebView

struct RefreshableWebView: View {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var webViewKey: UUID
    
    var body: some View {
        GeometryReader { geometry in
            WebViewContainer(
                url: url,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading
            )
            .id(webViewKey)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - WebView Container with UIKit Integration

struct WebViewContainer: UIViewControllerRepresentable {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    
    func makeUIViewController(context: Context) -> WebViewController {
        let controller = WebViewController()
        controller.url = url
        controller.canGoBackBinding = $canGoBack
        controller.canGoForwardBinding = $canGoForward
        controller.isLoadingBinding = $isLoading
        return controller
    }
    
    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {
        // Updates handled by WebViewController
    }
}

// MARK: - WebView UIViewController

import UIKit
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var refreshControl: UIRefreshControl!
    var url: URL!
    var canGoBackBinding: Binding<Bool>!
    var canGoForwardBinding: Binding<Bool>!
    var isLoadingBinding: Binding<Bool>!
    var lastBadgeCount: Int = 0
    var badgePollTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupRefreshControl()
        setupNotificationObservers()
        setupAppLifecycleObservers()
        
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }
    
    private func setupAppLifecycleObservers() {
        // Sync badge when app becomes active (returns from background)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Sync badge when app enters foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        print("📱 App became active, syncing badge...")
        syncBadgeFromBackend()
        startBadgePolling()
    }
    
    @objc private func appWillEnterForeground() {
        print("📱 App entering foreground, syncing badge...")
        syncBadgeFromBackend()
        startBadgePolling()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopBadgePolling()
    }
    
    private func startBadgePolling() {
        // Stop any existing timer
        stopBadgePolling()
        
        // Poll badge count every 30 seconds while app is active
        print("⏱️ Starting badge polling (every 30 seconds)")
        badgePollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            print("⏱️ Periodic badge sync...")
            self?.syncBadgeFromBackend()
        }
    }
    
    private func stopBadgePolling() {
        badgePollTimer?.invalidate()
        badgePollTimer = nil
        print("⏹️ Stopped badge polling")
    }
    
    private func syncBadgeFromBackend() {
        // Fetch badge count directly from backend API
        guard let url = URL(string: "https://blankee.example.com/get-unread-notification-count") else {
            print("❌ Invalid badge sync URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        // Copy cookies from WebView to URLSession request
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Badge sync failed: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("❌ No data received from badge sync")
                return
            }
            
            // Debug: Print raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("📋 Badge sync raw response: \(responseString.prefix(200))")
            }
            
            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 Badge sync HTTP status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("⚠️ Badge sync returned non-200 status: \(httpResponse.statusCode)")
                    return
                }
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let count = json["count"] as? Int {
                    print("✅ Badge synced from backend: \(count)")
                    
                    DispatchQueue.main.async {
                        // Check if badge increased (new notification while app was closed)
                        if count > self.lastBadgeCount && self.lastBadgeCount >= 0 {
                            let increase = count - self.lastBadgeCount
                            print("🆕 Detected \(increase) new notification(s) while app was closed")
                            let notificationBody = increase == 1 ?
                                "You have 1 new notification" :
                                "You have \(increase) new notifications"
                            NotificationManager.shared.showLocalNotification(
                                title: "Blankee",
                                body: notificationBody,
                                userInfo: ["badgeCount": count]
                            )
                        }
                        
                        self.lastBadgeCount = count
                        NotificationManager.shared.updateBadge(count: count)
                        
                        // Also update the web page badge if it's loaded
                        self.webView.evaluateJavaScript("""
                            if (window.nativeApp) {
                                console.log('🔄 Updating web badge from native sync: \(count)');
                            }
                        """)
                    }
                } else {
                    print("⚠️ Unexpected badge sync response format")
                }
            } catch {
                print("❌ Failed to parse badge sync response: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Blankee-iOS/1.0"
        
        let contentController = WKUserContentController()
        contentController.add(self, name: "nativeApp")
        
        // Inject JavaScript bridge initialization with notification support
        let bridgeScript = """
        console.log('🚀 iOS Native Bridge Initializing...');
        
        window.nativeApp = {
            postMessage: function(message) {
                window.webkit.messageHandlers.nativeApp.postMessage(message);
            },
            requestNotificationPermission: function() {
                this.postMessage({ action: 'requestNotificationPermission' });
            },
            log: function(message) {
                this.postMessage({ action: 'log', message: message });
            },
            haptic: function(style) {
                this.postMessage({ action: 'haptic', style: style || 'medium' });
            },
            sendNotification: function(title, body, data) {
                console.log('📬 Sending notification to iOS:', title, body);
                this.postMessage({ 
                    action: 'sendNotification', 
                    title: title, 
                    body: body, 
                    data: data || {} 
                });
            },
            updateBadge: function(count) {
                console.log('📛 Updating iOS badge to:', count);
                this.postMessage({ 
                    action: 'updateBadge', 
                    count: count 
                });
            }
        };
        
        console.log('✅ iOS Native Bridge Ready');
        
        // Setup notification interceptors after page loads
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                setupNotificationInterceptors();
            });
        } else {
            setupNotificationInterceptors();
        }
        
        function setupNotificationInterceptors() {
            console.log('🔧 Setting up web app notification interceptors...');
            
            // Intercept the web app's refreshNotificationBadge function
            var originalRefreshBadge = window.refreshNotificationBadge;
            if (typeof originalRefreshBadge === 'function') {
                window.refreshNotificationBadge = function() {
                    console.log('🔔 refreshNotificationBadge called');
                    originalRefreshBadge.apply(this, arguments);
                    
                    // Sync badge to iOS after web app updates it
                    setTimeout(function() {
                        var badgeElement = document.querySelector('.notification-badge');
                        if (badgeElement && badgeElement.textContent) {
                            var count = parseInt(badgeElement.textContent) || 0;
                            console.log('📊 Badge count from DOM:', count);
                            window.nativeApp.updateBadge(count);
                        }
                    }, 100);
                };
                console.log('✅ Intercepted refreshNotificationBadge');
            }
            
            // Monitor AJAX calls for notification changes
            if (typeof fetch !== 'undefined') {
                var originalFetch = window.fetch;
                window.fetch = function() {
                    var args = arguments;
                    var url = args[0];
                    
                    return originalFetch.apply(this, args).then(function(response) {
                        if (url && typeof url === 'string') {
                            if (url.includes('/save_totals_remainders') || 
                                url.includes('/mark-notification-read') ||
                                url.includes('/delete-notification')) {
                                console.log('🔔 Detected notification-related request:', url);
                                setTimeout(function() {
                                    window.nativeApp.postMessage({ 
                                        action: 'syncBadge' 
                                    });
                                }, 500);
                            }
                        }
                        return response;
                    });
                };
            }
            
            // Also intercept jQuery AJAX if available
            if (typeof $ !== 'undefined' && $.ajax) {
                var originalAjax = $.ajax;
                $.ajax = function(settings) {
                    var url = settings.url || '';
                    var complete = settings.complete;
                    
                    settings.complete = function() {
                        if (complete) complete.apply(this, arguments);
                        
                        if (url.includes('/save_totals_remainders') || 
                            url.includes('/mark-notification-read') ||
                            url.includes('/delete-notification')) {
                            console.log('🔔 Detected notification AJAX:', url);
                            setTimeout(function() {
                                window.nativeApp.postMessage({ 
                                    action: 'syncBadge' 
                                });
                            }, 500);
                        }
                    };
                    
                    return originalAjax.call(this, settings);
                };
            }
            
            console.log('✅ Web app notification interceptors ready');
        }
        """
        let userScript = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        
        configuration.userContentController = contentController
        
        // Configure default webpage preferences (JavaScript is enabled by default)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        view.addSubview(webView)
    }
    
    private func setupRefreshControl() {
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshWebView), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
        webView.scrollView.bounces = true
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(goBack), name: .webViewGoBack, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(goForward), name: .webViewGoForward, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWebView), name: .webViewReload, object: nil)
    }
    
    @objc private func refreshWebView() {
        webView.reload()
    }
    
    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoadingBinding.wrappedValue = true
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoadingBinding.wrappedValue = false
        canGoBackBinding.wrappedValue = webView.canGoBack
        canGoForwardBinding.wrappedValue = webView.canGoForward
        refreshControl.endRefreshing()
        
        // Start periodic badge polling
        startBadgePolling()
        
        // Sync badge count from web app after page loads
        print("🔄 Page loaded, syncing notification badge...")
        webView.evaluateJavaScript("""
            (function() {
                console.log('🔄 Page loaded, syncing badge...');
                if (typeof fetch !== 'undefined') {
                    fetch('/get-unread-notification-count')
                        .then(r => r.json())
                        .then(data => {
                            console.log('📊 Badge count from server:', data.count);
                            if (window.nativeApp && typeof data.count === 'number') {
                                window.nativeApp.updateBadge(data.count);
                            }
                        })
                        .catch(e => {
                            console.log('❌ Badge sync error:', e);
                        });
                } else {
                    console.log('⚠️ fetch not available');
                }
                console.log('✅ Badge sync JavaScript executed');
            })();
        """) { result, error in
            if let error = error {
                print("❌ Badge sync error: \(error.localizedDescription)")
            } else {
                print("✅ Badge sync JavaScript executed")
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoadingBinding.wrappedValue = false
        refreshControl.endRefreshing()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoadingBinding.wrappedValue = false
        refreshControl.endRefreshing()
    }
    
    // MARK: - WKUIDelegate
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nativeApp" else { return }
        
        if let body = message.body as? [String: Any] {
            handleJavaScriptMessage(body)
        }
    }
    
    private func handleJavaScriptMessage(_ message: [String: Any]) {
        print("📨 Received message from JavaScript: \(message)")
        
        if let action = message["action"] as? String {
            switch action {
            case "requestNotificationPermission":
                NotificationManager.shared.requestAuthorization()
                
            case "log":
                if let logMessage = message["message"] as? String {
                    print("JS Log: \(logMessage)")
                }
                
            case "haptic":
                if let style = message["style"] as? String {
                    triggerHaptic(style: style)
                }
                
            case "sendNotification":
                let title = message["title"] as? String ?? "Blankee"
                let body = message["body"] as? String ?? ""
                let data = message["data"] as? [String: Any] ?? [:]
                print("📬 Sending local notification: \(title) - \(body)")
                NotificationManager.shared.showLocalNotification(title: title, body: body, userInfo: data)
                
            case "updateBadge":
                if let count = message["count"] as? Int {
                    print("📛 Updating badge to: \(count)")
                    
                    // Check if badge increased (new notification)
                    if count > lastBadgeCount && lastBadgeCount >= 0 {
                        let increase = count - lastBadgeCount
                        print("🆕 Badge increased by \(increase), triggering notification")
                        let notificationBody = increase == 1 ?
                            "You have 1 new notification" :
                            "You have \(increase) new notifications"
                        NotificationManager.shared.showLocalNotification(
                            title: "Blankee",
                            body: notificationBody,
                            userInfo: ["badgeCount": count]
                        )
                    }
                    
                    lastBadgeCount = count
                    NotificationManager.shared.updateBadge(count: count)
                }
                
            case "syncBadge":
                print("🔄 Syncing badge after notification change...")
                webView.evaluateJavaScript("""
                    (function() {
                        if (typeof fetch !== 'undefined') {
                            fetch('/get-unread-notification-count')
                                .then(r => r.json())
                                .then(data => {
                                    console.log('📊 Badge count from server:', data.count);
                                    if (window.nativeApp && typeof data.count === 'number') {
                                        window.nativeApp.updateBadge(data.count);
                                    }
                                })
                                .catch(e => console.log('❌ Badge sync error:', e));
                        }
                    })();
                """)
                
            default:
                print("⚠️ Unknown action: \(action)")
            }
        }
    }
    
    private func triggerHaptic(style: String) {
        let generator = UIImpactFeedbackGenerator(style: {
            switch style {
            case "light": return .light
            case "medium": return .medium
            case "heavy": return .heavy
            default: return .medium
            }
        }())
        generator.impactOccurred()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Navigation Toolbar (COMMENTED OUT)
// Uncomment this entire section to re-enable the navigation toolbar

/*
struct NavigationToolbar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1.0 : 0.3)
            
            Divider()
            
            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1.0 : 0.3)
            
            Divider()
            
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
        .frame(height: 44)
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .top
        )
    }
}

To re-enable the toolbar: Just uncomment the two marked sections and move the .ignoresSafeArea() modifier back to the VStack.
*/

// MARK: - Notification Names

extension Notification.Name {
    static let webViewGoBack = Notification.Name("webViewGoBack")
    static let webViewGoForward = Notification.Name("webViewGoForward")
    static let webViewReload = Notification.Name("webViewReload")
}

#Preview {
    ContentView()
}
