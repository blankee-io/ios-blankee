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
    
    let webURL = URL(string: "https://blankee.example.com")!
    
    var body: some View {
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupRefreshControl()
        setupNotificationObservers()
        
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Blankee-iOS/1.0"
        
        let contentController = WKUserContentController()
        contentController.add(self, name: "nativeApp")
        
        // Inject JavaScript bridge initialization
        let bridgeScript = """
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
            }
        };
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
        print("Received message from JavaScript: \(message)")
        
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
            default:
                print("Unknown action: \(action)")
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
