//
//  ServerSetupView.swift
//  blankee.app
//
//  Where the user says which Blankee server to load - at first launch, and
//  again any time they want to point somewhere else. Laid out to match the web
//  app's login page: teal nav bar and wordmark, white card, the same inputs and
//  buttons. See BlankeeTheme for where each value comes from.
//

import SwiftUI

struct ServerSetupView: View {
    enum Mode {
        /// Nothing saved yet: this is the whole screen, and there is no way out
        /// except entering a server.
        case firstRun
        /// Presented as a sheet over the running web app.
        case change
    }
    
    let mode: Mode
    
    @ObservedObject private var settings = ServerSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var address = ""
    @State private var validationMessage: String?
    @State private var isTesting = false
    @State private var unreachable: UnreachableServer?
    @FocusState private var addressFocused: Bool
    
    init(mode: Mode) {
        self.mode = mode
    }
    
    var body: some View {
        ZStack {
            Color.blankeeBgPage.ignoresSafeArea()
            
            VStack(spacing: 0) {
                BlankeeNavBar()
                
                ScrollView {
                    BlankeeCard {
                        header
                        addressRow
                        helperText
                        connectButton
                        secondaryActions
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .alert(
            "Could not reach \(unreachable?.host ?? "the server")",
            isPresented: Binding(
                get: { unreachable != nil },
                set: { if !$0 { unreachable = nil } }
            ),
            presenting: unreachable
        ) { server in
            Button("Use it anyway") {
                settings.save(server.url)
                dismiss()
            }
            Button("Edit address", role: .cancel) {
                addressFocused = true
            }
        } message: { server in
            Text(server.detail)
        }
        .onAppear {
            if address.isEmpty, let current = settings.serverURL {
                address = current.absoluteString
            }
            if mode == .firstRun {
                addressFocused = true
            }
        }
    }
    
    // MARK: - Pieces
    
    private var header: some View {
        VStack(spacing: 8) {
            Text(mode == .firstRun ? "Connect" : "Your Server")
                .font(BlankeeFont.semibold(28))
                .foregroundStyle(Color.blankeeTextDark)
                .kerning(-0.5)
            
            Text("Blankee is self-hosted. Enter the address of your own server.")
                .font(BlankeeFont.regular(12))
                .foregroundStyle(Color.blankeeSecondaryDark)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    /// .login-row: label on the left at a fixed width, field filling the rest.
    private var addressRow: some View {
        HStack(spacing: 10) {
            Text("Server:")
                .font(BlankeeFont.regular(12))
                .foregroundStyle(Color.blankeeTextDark)
                .frame(width: 60, alignment: .trailing)
            
            TextField("", text: $address, prompt: placeholder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit(connect)
                .onChange(of: address) { _, _ in validationMessage = nil }
                .blankeeInput(isFocused: addressFocused)
        }
    }
    
    private var placeholder: Text {
        Text("192.168.1.50:18420")
            .font(BlankeeFont.regular(14))
            .foregroundColor(Color.blankeeSecondary)
    }
    
    private var helperText: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let validationMessage {
                Text(validationMessage)
                    .font(BlankeeFont.regular(12))
                    .foregroundStyle(Color.blankeeDanger)
            }
            
            Text("An address on your network, with a port if it uses one, or a domain name. https:// is assumed unless the address is on your local network.")
                .font(BlankeeFont.regular(12))
                .foregroundStyle(Color.blankeeSecondaryDark)
            
            // Written out rather than interpolated so SwiftUI does not turn the
            // examples into tappable links.
            Text(verbatim: "Examples: 192.168.1.50:18420, blankee.local, budget.example.com")
                .font(BlankeeFont.regular(12))
                .foregroundStyle(Color.blankeeSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: 10) {
                Text(mode == .firstRun ? "Connect" : "Save and reload")
                if isTesting {
                    BlankeeSpinner(diameter: 22, showsRing: false)
                        .foregroundStyle(Color.blankeeTextLight)
                }
            }
        }
        .buttonStyle(BlankeePrimaryButtonStyle(isEnabled: canConnect))
        .disabled(!canConnect)
        .padding(.top, 4)
    }
    
    private var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && !isTesting
    }
    
    @ViewBuilder
    private var secondaryActions: some View {
        if mode == .firstRun {
            Text("You can change this later with a two-finger long press anywhere in the app.")
                .font(BlankeeFont.regular(12))
                .foregroundStyle(Color.blankeeSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        } else {
            VStack(spacing: 14) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(BlankeeSecondaryButtonStyle())
                
                if let current = settings.serverURL {
                    VStack(spacing: 6) {
                        Text("Currently connected to")
                            .font(BlankeeFont.regular(12))
                            .foregroundStyle(Color.blankeeSecondary)
                        Text(verbatim: current.absoluteString)
                            .font(BlankeeFont.semibold(12))
                            .foregroundStyle(Color.blankeeTextDark)
                        
                        Button("Forget this server") {
                            settings.forget()
                            dismiss()
                        }
                        .font(BlankeeFont.semibold(12))
                        .foregroundStyle(Color.blankeeDanger)
                        .padding(.top, 2)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func connect() {
        guard !isTesting else { return }
        
        let url: URL
        do {
            url = try ServerAddress.normalize(address)
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        
        validationMessage = nil
        addressFocused = false
        isTesting = true
        
        Task {
            let result = await ServerAddress.probe(url)
            await MainActor.run {
                isTesting = false
                // Show what was actually resolved, so a guessed scheme is visible.
                address = url.absoluteString
                
                if result.reachable {
                    settings.save(url)
                    if mode == .change {
                        dismiss()
                    }
                } else {
                    unreachable = UnreachableServer(
                        url: url,
                        host: url.host ?? url.absoluteString,
                        detail: result.detail ?? "The server did not answer."
                    )
                }
            }
        }
    }
}

// MARK: - Alert Payload

private struct UnreachableServer: Identifiable {
    let id = UUID()
    let url: URL
    let host: String
    let detail: String
}

#Preview("First run") {
    ServerSetupView(mode: .firstRun)
}

#Preview("Change server") {
    ServerSetupView(mode: .change)
}
