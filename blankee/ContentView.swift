// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  ContentView.swift
//  blankee.app
//
//  Created by Camden Zupon on 10/26/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @StateObject private var settings = ServerSettings.shared
    @State private var showingError = false
    @State private var loadError: WebLoadError?
    @State private var hasRendered = false
    @State private var showingServerSettings = false
    @State private var webViewKey = UUID()
    
    var body: some View {
        Group {
            if let serverURL = settings.serverURL {
                webApp(serverURL: serverURL)
            } else {
                // Nothing saved yet, so setup is the whole app.
                ServerSetupView(mode: .firstRun)
            }
        }
        .sheet(isPresented: $showingServerSettings) {
            ServerSetupView(mode: .change)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openServerSettings)) { _ in
            showingServerSettings = true
        }
        .onOpenURL { url in
            // blankee://dashboard_d, from the home screen widget. The host is
            // the page to show; the web view is already pointed at the right
            // server, so only the path travels.
            guard url.scheme == "blankee", let page = url.host, !page.isEmpty else { return }
            NotificationCenter.default.post(name: .openWebPath, object: "/" + page)
        }
        .onChange(of: settings.serverURL) { previousServer, newServer in
            guard newServer != nil else { return }
            // A different server knows nothing of the old one's unread count,
            // and has never heard of this device.
            loadError = nil
            hasRendered = false
            NotificationManager.shared.updateBadge(count: 0)
            NotificationManager.shared.resendDeviceToken()
            // The widget's token was issued by the old server and means nothing
            // to the new one.
            WidgetBridge.serverChanged(to: newServer, previous: previousServer)
        }
    }
    
    private func webApp(serverURL: URL) -> some View {
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
                    url: serverURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    loadError: $loadError,
                    hasRendered: $hasRendered,
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
        .overlay {
            if loadError == nil && !hasRendered {
                BlankeeConnectingView(host: serverURL.host ?? serverURL.absoluteString)
            }
        }
        .overlay {
            if let loadError {
                ServerUnreachableView(
                    error: loadError,
                    onRetry: {
                        self.loadError = nil
                        NotificationCenter.default.post(name: .webViewReload, object: nil)
                    },
                    onChangeServer: {
                        showingServerSettings = true
                    }
                )
            }
        }
    }
}

// MARK: - Connecting

/// Shown while the first page is still on its way. Without it the app is a
/// blank white rectangle for as long as the server takes to answer.
struct BlankeeConnectingView: View {
    let host: String
    
    var body: some View {
        VStack(spacing: 20) {
            BlankeeSpinner(diameter: 48)
            
            Text("Connecting to \(host)")
                .font(BlankeeFont.regular(14))
                .foregroundStyle(Color.blankeeSecondaryDark)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blankeeBgPage)
    }
}

// MARK: - Load Failure

struct WebLoadError: Equatable {
    let host: String
    let message: String
}

/// Shown instead of a blank web view when the server does not answer - and the
/// only way back to the settings when the saved address is the thing that is wrong.
struct ServerUnreachableView: View {
    let error: WebLoadError
    let onRetry: () -> Void
    let onChangeServer: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            BlankeeNavBar()
            
            Spacer(minLength: 0)
            
            BlankeeCard {
                Text(FAIcon.triangleExclamation)
                    .font(BlankeeFont.awesome(40))
                    .foregroundStyle(Color.blankeeAccent)
                
                Text("Can't reach \(error.host)")
                    .font(BlankeeFont.semibold(22))
                    .foregroundStyle(Color.blankeeTextDark)
                    .multilineTextAlignment(.center)
                
                Text(error.message)
                    .font(BlankeeFont.regular(12))
                    .foregroundStyle(Color.blankeeSecondaryDark)
                    .multilineTextAlignment(.center)
                
                Button("Try again", action: onRetry)
                    .buttonStyle(BlankeePrimaryButtonStyle())
                    .padding(.top, 4)
                
                Button("Change server", action: onChangeServer)
                    .buttonStyle(BlankeeSecondaryButtonStyle())
            }
            .padding(.horizontal, 16)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blankeeBgPage)
    }
}

// MARK: - Refreshable WebView

struct RefreshableWebView: View {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var loadError: WebLoadError?
    @Binding var hasRendered: Bool
    @Binding var webViewKey: UUID
    
    var body: some View {
        GeometryReader { geometry in
            WebViewContainer(
                url: url,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading,
                loadError: $loadError,
                hasRendered: $hasRendered
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
    @Binding var loadError: WebLoadError?
    @Binding var hasRendered: Bool
    
    func makeUIViewController(context: Context) -> WebViewController {
        let controller = WebViewController()
        controller.url = url
        controller.canGoBackBinding = $canGoBack
        controller.canGoForwardBinding = $canGoForward
        controller.isLoadingBinding = $isLoading
        controller.loadErrorBinding = $loadError
        controller.hasRenderedBinding = $hasRendered
        return controller
    }
    
    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {
        uiViewController.loadErrorBinding = $loadError
        uiViewController.hasRenderedBinding = $hasRendered
        // Keeps the same web view when the user points the app at another server.
        guard uiViewController.url != url else { return }
        // Deferred: loading clears the error state, which must not happen in
        // the middle of a SwiftUI update.
        let target = url
        DispatchQueue.main.async {
            uiViewController.load(target)
        }
    }
}

// MARK: - WebView UIViewController

import UIKit
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    var webView: WKWebView!
    var refreshControl: UIRefreshControl!
    var url: URL!
    var canGoBackBinding: Binding<Bool>!
    var canGoForwardBinding: Binding<Bool>!
    var isLoadingBinding: Binding<Bool>!
    var loadErrorBinding: Binding<WebLoadError?>!
    var hasRenderedBinding: Binding<Bool>!
    var lastBadgeCount: Int = 0
    var badgePollTimer: Timer?
    var loadWatchdog: Timer?
    
    /// How long to wait for the server before giving up and saying so. WebKit's
    /// own timeout is about a minute, which reads as a hung app when the address
    /// is simply wrong.
    static let loadTimeout: TimeInterval = 15
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupRefreshControl()
        setupSettingsGesture()
        setupNotificationObservers()
        setupAppLifecycleObservers()
        
        if let url = url {
            // A notification tap that launched the app arrived before there was
            // a web view to hear it; start on its page rather than the landing
            // page. Cleared here so a later reload does not go back to it.
            if let path = NotificationManager.shared.pendingWebPath,
               let target = URL(string: url.absoluteString + path) {
                NotificationManager.shared.pendingWebPath = nil
                startLoad(target)
            } else {
                startLoad(url)
            }
        }
    }
    
    /// Loads a different server, or does nothing if it is the one already showing.
    func load(_ newURL: URL) {
        guard url != newURL else { return }
        url = newURL
        lastBadgeCount = 0
        loadErrorBinding?.wrappedValue = nil
        hasRenderedBinding?.wrappedValue = false
        startLoad(newURL)
    }
    
    private func startLoad(_ target: URL) {
        let request = URLRequest(
            url: target,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: WebViewController.loadTimeout
        )
        webView.load(request)
    }
    
    /// WebKit does not reliably honour a request's timeoutInterval, so time the
    /// load here as well and stop it ourselves.
    private func startWatchdog() {
        stopWatchdog()
        loadWatchdog = Timer.scheduledTimer(
            withTimeInterval: WebViewController.loadTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            self.webView.stopLoading()
            self.isLoadingBinding.wrappedValue = false
            self.refreshControl.endRefreshing()
            print("⏱️ Load timed out after \(Int(WebViewController.loadTimeout))s")
            self.loadErrorBinding?.wrappedValue = WebLoadError(
                host: self.url?.host ?? "the server",
                message: "The server did not answer within \(Int(WebViewController.loadTimeout)) seconds."
            )
        }
    }
    
    private func stopWatchdog() {
        loadWatchdog?.invalidate()
        loadWatchdog = nil
    }
    
    /// Two fingers held down opens the server settings. Two fingers because one
    /// belongs to the web app - this must not swallow taps or text selection.
    private func setupSettingsGesture() {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleSettingsGesture))
        recognizer.numberOfTouchesRequired = 2
        recognizer.minimumPressDuration = 0.6
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        webView.addGestureRecognizer(recognizer)
    }
    
    @objc private func handleSettingsGesture(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        triggerHaptic(style: "medium")
        NotificationCenter.default.post(name: .openServerSettings, object: nil)
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
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
        // Fetch badge count from the server the user configured
        guard let url = Config.unreadNotificationCountURL else {
            print("❌ No server configured, skipping badge sync")
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
                        // The count only moves the badge. It used to raise a local
                        // "You have N new notifications" alert whenever it had
                        // risen since the app last looked - a stand-in for push
                        // from before push worked. Now every notification arrives
                        // as its own push, with its own text, so that alert was a
                        // second buzz for the same thing, and one on every launch
                        // with anything unread.
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
            },
            openServerSettings: function() {
                this.postMessage({ action: 'openServerSettings' });
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

        // Tells the widget when the page has just saved something.
        //
        // The web app saves over AJAX and almost never navigates, so didFinish -
        // the only other place a reload is triggered from - fires on launch and
        // then essentially never again. Without this, adding an entry left the
        // widget showing the old figures until its next 15-minute tick.
        //
        // Injected from here rather than added to the web app: a WKUserScript
        // reaches the page's own JavaScript without changing a file on the
        // server, which keeps this entirely inside the iOS app.
        let widgetWatchScript = """
        (function() {
            if (window.__blankeeWidgetWatch) { return; }
            window.__blankeeWidgetWatch = true;

            var timer = null;
            function changed() {
                // One message per burst: saving a row fires several requests,
                // and each reload spends from the widget's refresh budget.
                clearTimeout(timer);
                timer = setTimeout(function() {
                    if (window.nativeApp) { window.nativeApp.postMessage({ action: 'dataChanged' }); }
                }, 1200);
            }

            function mutating(method) {
                if (!method) { return false; }
                var m = String(method).toUpperCase();
                return m !== 'GET' && m !== 'HEAD' && m !== 'OPTIONS';
            }

            var open = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method) {
                this.__blankeeMutating = mutating(method);
                return open.apply(this, arguments);
            };

            var send = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
                if (this.__blankeeMutating) {
                    this.addEventListener('loadend', function() {
                        if (this.status >= 200 && this.status < 300) { changed(); }
                    });
                }
                return send.apply(this, arguments);
            };

            if (window.fetch) {
                var fetch0 = window.fetch;
                window.fetch = function(input, init) {
                    var method = (init && init.method) || (input && input.method) || 'GET';
                    var p = fetch0.apply(this, arguments);
                    if (mutating(method)) {
                        p.then(function(r) { if (r && r.ok) { changed(); } }).catch(function() {});
                    }
                    return p;
                };
            }
        })();
        """
        contentController.addUserScript(
            WKUserScript(source: widgetWatchScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        
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
        NotificationCenter.default.addObserver(self, selector: #selector(openWebPath(_:)), name: .openWebPath, object: nil)
    }

    /// Navigates to a path on the server already loaded, which is what a widget
    /// tap amounts to. Resolved against `url` rather than the web view's
    /// current address so that a sub-path server - https://example.com/blankee
    /// - keeps its prefix.
    @objc private func openWebPath(_ note: Notification) {
        guard let path = note.object as? String, let base = url else { return }
        // Heard live, so the launch-time copy is spent.
        NotificationManager.shared.pendingWebPath = nil
        guard let target = URL(string: base.absoluteString + path) else { return }
        loadErrorBinding?.wrappedValue = nil
        webView.load(URLRequest(url: target, cachePolicy: .useProtocolCachePolicy,
                                timeoutInterval: WebViewController.loadTimeout))
    }
    
    @objc private func refreshWebView() {
        if webView.url == nil, let url = url {
            // The first attempt never landed, so there is nothing to reload.
            startLoad(url)
        } else {
            webView.reload()
        }
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
        loadErrorBinding?.wrappedValue = nil
        startWatchdog()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        stopWatchdog()
        isLoadingBinding.wrappedValue = false
        hasRenderedBinding?.wrappedValue = true
        canGoBackBinding.wrappedValue = webView.canGoBack
        canGoForwardBinding.wrappedValue = webView.canGoForward
        refreshControl.endRefreshing()
        
        // Start periodic badge polling
        startBadgePolling()

        // The widget reads the server directly, but only the app can mint it a
        // token, and only the app knows an edit just happened. Both are handled
        // here, so the home screen follows the app rather than its own timer.
        if let serverURL = url {
            WidgetBridge.webViewDidFinishLoad(webView, serverURL: serverURL)
            // Same moment, same reason: a signed-in page is when the device can
            // be registered for push, and the token may have arrived before it.
            NotificationManager.shared.ensureRegistered()
        }
        
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
        reportLoadFailure(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportLoadFailure(error)
    }
    
    private func reportLoadFailure(_ error: Error) {
        stopWatchdog()
        isLoadingBinding.wrappedValue = false
        refreshControl.endRefreshing()
        
        let nsError = error as NSError
        // A cancelled load is usually the next navigation starting, not a failure.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        
        print("❌ Load failed: \(nsError.localizedDescription)")
        loadErrorBinding?.wrappedValue = WebLoadError(
            host: url?.host ?? "the server",
            message: nsError.localizedDescription
        )
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
            case "dataChanged":
                WidgetBridge.dataDidChange()
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
                    // Badge only - see the badge sync above for why no alert.
                    lastBadgeCount = count
                    NotificationManager.shared.updateBadge(count: count)
                }
                
            case "openServerSettings":
                NotificationCenter.default.post(name: .openServerSettings, object: nil)
                
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
        loadWatchdog?.invalidate()
        badgePollTimer?.invalidate()
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
    static let openServerSettings = Notification.Name("openServerSettings")
    /// Sent when the home screen widget is tapped. The object is the path to
    /// open, so one name covers any widget added later.
    static let openWebPath = Notification.Name("openWebPath")
}

#Preview {
    ContentView()
}
