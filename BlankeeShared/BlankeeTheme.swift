//
//  BlankeeTheme.swift
//  blankee.app
//
//  The web app's look, in Swift. Every value here is copied from the web app's
//  static/css/style.css so the two do not drift apart by accident: the colours
//  are its :root custom properties, the metrics are its .logincontainer,
//  .login-input and .login-button rules, and the fonts are the same files it
//  serves - Nunito, and Font Awesome Free for icons.
//

import SwiftUI
import CoreText

// MARK: - Colours (style.css :root)

extension Color {
    static let blankeeWhite            = Color(hex: 0xFFFFFF)
    static let blankeeBgPage           = Color(hex: 0xF2F7F7)
    
    static let blankeePrimary          = Color(hex: 0x2AAAA8)
    static let blankeePrimaryMid       = Color(hex: 0x42C0BE)
    static let blankeePrimaryHover     = Color(hex: 0x59D6D4)
    static let blankeePrimaryLighter   = Color(hex: 0xE6FAF9)
    
    static let blankeeSecondary        = Color(hex: 0xA9A9A9)
    static let blankeeSecondaryDark    = Color(hex: 0x676767)
    static let blankeeSecondaryHover   = Color(hex: 0xD3D3D3)
    static let blankeeSecondaryLighter = Color(hex: 0xF4F4F4)
    
    static let blankeeAccent           = Color(hex: 0xE45F1C)
    static let blankeeAccentMid        = Color(hex: 0xEA7F4A)
    static let blankeeAccentHover      = Color(hex: 0xEF9F77)
    static let blankeeAccentLighter    = Color(hex: 0xFDEEEE)

    static let blankeeWarning          = Color(hex: 0xD89802)

    static let blankeeTextDark         = Color(hex: 0x575757)
    static let blankeeTextLight        = Color(hex: 0xFFFFFF)
    static let blankeeDanger           = Color(hex: 0xF94449)
    static let blankeeSuccess          = Color(hex: 0x28A745)
    
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Fonts

enum BlankeeFont {
    /// Registers the bundled fonts with CoreText. Called once, before any view
    /// asks for them; the web fonts are the same files the web app serves, and
    /// CoreText reads .woff2 directly, so they are copied rather than converted.
    static func registerAll() {
        _ = registered
    }
    
    private static let registered: Bool = {
        let files = [
            ("Nunito-Regular", "ttf"),
            ("Nunito-SemiBold", "ttf"),
            ("Nunito-Bold", "ttf"),
            ("fa-solid-900", "woff2"),
            ("fa-regular-400", "woff2"),
        ]
        for (name, ext) in files {
            guard let url = locate(name, ext) else {
                print("⚠️ Font missing from bundle: \(name).\(ext)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered is not a failure worth shouting about.
                let code = CFErrorGetCode(error?.takeUnretainedValue())
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    print("⚠️ Could not register \(name).\(ext): code \(code)")
                }
            }
        }
        return true
    }()
    
    /// Resources from a synchronized folder land at the bundle root, but do not
    /// count on it - look in the subdirectories they came from as well.
    private static func locate(_ name: String, _ ext: String) -> URL? {
        let subdirectories = [nil, "Fonts", "FontAwesome/webfonts", "webfonts"]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
    
    // Nunito, as the web app declares it: 400, 600 and 700.
    static func regular(_ size: CGFloat) -> Font {
        registerAll()
        return .custom("Nunito-Regular", size: size)
    }
    
    static func semibold(_ size: CGFloat) -> Font {
        registerAll()
        return .custom("Nunito-SemiBold", size: size)
    }
    
    static func bold(_ size: CGFloat) -> Font {
        registerAll()
        return .custom("Nunito-Bold", size: size)
    }
    
    static func awesome(_ size: CGFloat) -> Font {
        registerAll()
        return .custom("FontAwesome7Free-Solid", size: size)
    }
}

/// Font Awesome Free glyphs, by the names the web app uses for them.
enum FAIcon {
    /// fa-spinner. The web app asks for fa-spinner-scale, which is Pro; its own
    /// fa-pro-fallback.css maps that to this Free glyph, so this matches what a
    /// Free install of the web app draws.
    static let spinner = "\u{f110}"
    /// fa-wifi-slash's Free stand-in: fa-triangle-exclamation.
    static let triangleExclamation = "\u{f071}"
    /// fa-server
    static let server = "\u{f233}"

    // The calendar navigation in the page header. The web app asks for fa-left
    // and fa-right, which are Pro and absent from the Free faces bundled here,
    // so these are the circled arrows its own fa-pro-fallback.css substitutes
    // for a Free install of the site.
    /// fa-circle-left, standing in for the page's Pro fa-left
    static let circleLeft = "\u{f359}"
    /// fa-circle-right, standing in for the page's Pro fa-right
    static let circleRight = "\u{f35a}"
    /// fa-calendar-day
    static let calendarDay = "\u{f783}"
    /// fa-check, the glyph in the page's paid badge (.paid::after)
    static let check = "\u{f00c}"

    // The trend widget's header: the summary page's section icons and its
    // trend arrow. All Free Solid.
    static let chartLine = "\u{f201}"
    static let creditCard = "\u{f09d}"
    static let piggyBank = "\u{f4d3}"
    static let arrowTrendUp = "\u{e098}"
    static let arrowTrendDown = "\u{e097}"
    static let minus = "\u{f068}"
}

// MARK: - Spinner (style.css .spinner-circle / #loading-spinner)

/// The web app's loading spinner: a Font Awesome spinner on a primary-coloured
/// disc, stepping through eight positions a second the way fa-spin-pulse does.
struct BlankeeSpinner: View {
    var diameter: CGFloat = 48
    var showsRing: Bool = true
    
    @State private var step = 0
    
    private let timer = Timer.publish(every: 0.125, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(FAIcon.spinner)
            .font(BlankeeFont.awesome(diameter * 0.46))
            .foregroundStyle(showsRing ? Color.blankeeBgPage : Color.blankeePrimary)
            .rotationEffect(.degrees(Double(step) * 45))
            .frame(width: diameter, height: diameter)
            .background {
                if showsRing {
                    Circle()
                        .fill(Color.blankeePrimary)
                        .overlay(Circle().strokeBorder(Color.blankeeBgPage, lineWidth: 4))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
            }
            .onReceive(timer) { _ in
                step = (step + 1) % 8
            }
            .accessibilityLabel("Connecting")
    }
}

// MARK: - Controls (style.css .login-input / .login-button)

/// .login-input: 48pt tall, 10pt radius, grey border that turns primary with a
/// soft ring on focus.
struct BlankeeInputStyle: ViewModifier {
    var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .font(BlankeeFont.regular(14))
            .foregroundStyle(Color.blankeeTextDark)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.blankeeWhite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.blankeePrimary : Color.blankeeSecondaryHover,
                        lineWidth: 1
                    )
            }
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.blankeePrimaryLighter, lineWidth: 3)
                        .padding(-1.5)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    func blankeeInput(isFocused: Bool) -> some View {
        modifier(BlankeeInputStyle(isFocused: isFocused))
    }
}

/// .login-button: full width, 12pt radius, primary fill, 18pt semibold white.
struct BlankeePrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BlankeeFont.semibold(18))
            .foregroundStyle(Color.blankeeTextLight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(
                fill(pressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .shadow(
                color: .black.opacity(0.14),
                radius: configuration.isPressed ? 4 : 6,
                y: configuration.isPressed ? 1 : 2
            )
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
    
    private func fill(pressed: Bool) -> Color {
        guard isEnabled else { return .blankeeSecondaryHover }
        return pressed ? .blankeePrimaryHover : .blankeePrimary
    }
}

/// The quieter second button - same shape, primary as an outline rather than a fill.
struct BlankeeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BlankeeFont.semibold(18))
            .foregroundStyle(Color.blankeePrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(
                (configuration.isPressed ? Color.blankeePrimaryLighter : Color.blankeeWhite),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.blankeePrimary, lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Chrome (style.css .nav-bar / .logincontainer)

/// .nav-bar-login: 50pt of primary with the wordmark centred, 38pt tall.
struct BlankeeNavBar: View {
    var body: some View {
        ZStack {
            Image("BlankeeLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 38)
                .accessibilityLabel("Blankee")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        // Teal carries on up behind the status bar, as the sticky nav does.
        .background(Color.blankeePrimary.ignoresSafeArea(edges: .top))
    }
}

/// .logincontainer: white card, 16pt radius, soft shadow, 450pt at its widest.
struct BlankeeCard<Content: View>: View {
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: 450)
        .background(Color.blankeeWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 20, y: 4)
    }
}
