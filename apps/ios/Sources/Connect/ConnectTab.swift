import OpenClawKit
import SwiftUI

struct ConnectTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("gateway.manual.port") private var manualGatewayPort: Int = 18789
    @AppStorage("gateway.manual.tls") private var manualGatewayTLS: Bool = true
    @AppStorage("gateway.setupCode") private var setupCode: String = ""
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString

    // Expanded by default
    @State private var gatewayExpanded: Bool = true
    @State private var connecting: Bool = false
    @State private var connectingGatewayID: String?
    @State private var connectError: String?
    @State private var gatewayToken: String = ""
    @State private var gatewayPassword: String = ""
    @State private var setupStatusText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection Control")
                            .font(.headline)
                            .foregroundStyle(Color.openClawAccent)
                        Text("Gateway Connection")
                            .font(.title2.bold())
                            .foregroundStyle(Color.openClawText)
                        Text("One primary action. Open advanced controls only when needed.")
                            .font(.footnote)
                            .foregroundStyle(Color.openClawSecondaryText)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.bottom, 8)

                    LabeledContent {
                        Text(self.activeEndpoint)
                            .foregroundStyle(Color.openClawText)
                    } label: {
                        Text("Active endpoint")
                            .foregroundStyle(Color.openClawSecondaryText)
                    }

                    LabeledContent {
                        Text(self.appModel.gatewayStatusText)
                            .foregroundStyle(Color.openClawText)
                    } label: {
                        Text("Gateway state")
                            .foregroundStyle(Color.openClawSecondaryText)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if self.isGatewayConnected {
                                self.appModel.disconnectGateway()
                            } else {
                                Task { await self.connectManual() }
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if self.connecting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text(self.isGatewayConnected ? "Disconnect Gateway" : "Connect Gateway")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(self.isGatewayConnected ? Color.red : Color.openClawAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)

                    if let error = self.connectError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.clear)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    DisclosureGroup(
                        isExpanded: self.$gatewayExpanded,
                        content: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Setup Code")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.openClawSecondaryText)

                                HStack {
                                    TextField("Paste setup code", text: self.$setupCode)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()

                                    Button("Apply") {
                                        withAnimation {
                                            self.applySetupCode()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(self.setupCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }

                                if let status = self.setupStatusText {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(status.lowercased().contains("failed") ? .red : Color.openClawSecondaryText)
                                        .transition(.opacity)
                                }

                                Divider()
                                    .overlay(Color.openClawSecondaryText.opacity(0.2))

                                Text("Manual Connection")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.openClawSecondaryText)

                                HStack {
                                    TextField("Host", text: self.$manualGatewayHost)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    TextField("Port", value: self.$manualGatewayPort, format: .number.grouping(.never))
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                        .frame(width: 80)
                                }

                                Toggle("Use TLS", isOn: self.$manualGatewayTLS)
                                    .foregroundStyle(Color.openClawText)

                                TextField("Token (optional)", text: self.$gatewayToken)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: self.gatewayToken) { _, newValue in
                                        self.saveCredentials(token: newValue, password: self.gatewayPassword)
                                    }

                                SecureField("Password (optional)", text: self.$gatewayPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: self.gatewayPassword) { _, newValue in
                                        self.saveCredentials(token: self.gatewayToken, password: newValue)
                                    }
                            }
                            .padding(.vertical, 8)
                        },
                        label: {
                            Text("Advanced controls")
                                .foregroundStyle(Color.openClawText)
                        }
                    )
                }
                .listRowBackground(Color.openClawSurface)

                if !self.gatewayController.gateways.isEmpty {
                    Section {
                        ForEach(self.gatewayController.gateways) { gateway in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(gateway.name)
                                        .font(.headline)
                                        .foregroundStyle(Color.openClawText)
                                    Text(gateway.stableID)
                                        .font(.caption)
                                        .foregroundStyle(Color.openClawSecondaryText)
                                }
                                Spacer()
                                Button("Connect") {
                                    Task { await self.connectDiscovered(gateway) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(self.connectingGatewayID != nil)
                            }
                        }
                    } header: {
                        Text("Discovered Gateways")
                            .foregroundStyle(Color.openClawSecondaryText)
                    }
                    .listRowBackground(Color.openClawSurface)
                }
            }
            .navigationBarHidden(true)
            .background(Color.openClawBackground)
            .scrollContentBackground(.hidden)
            .onAppear {
                self.loadCredentials()
            }
        }
    }

    private var isGatewayConnected: Bool {
        self.appModel.gatewayServerName != nil
    }

    private var activeEndpoint: String {
        if let server = self.appModel.gatewayServerName {
            return server
        }
        if self.manualGatewayEnabled {
            let port = self.manualGatewayTLS && self.manualGatewayPort == 0 ? 443 : self.manualGatewayPort
            return "\(self.manualGatewayHost):\(port)"
        }
        return "Not set"
    }

    private func loadCredentials() {
        let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstanceId.isEmpty {
            self.gatewayToken = GatewaySettingsStore.loadGatewayToken(instanceId: trimmedInstanceId) ?? ""
            self.gatewayPassword = GatewaySettingsStore.loadGatewayPassword(instanceId: trimmedInstanceId) ?? ""
        }
    }

    private func saveCredentials(token: String, password: String) {
        let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstanceId.isEmpty else { return }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        GatewaySettingsStore.saveGatewayToken(trimmedToken, instanceId: trimmedInstanceId)

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        GatewaySettingsStore.saveGatewayPassword(trimmedPassword, instanceId: trimmedInstanceId)
    }

    private func connectManual() async {
        withAnimation {
            self.connecting = true
            self.connectError = nil
        }
        self.manualGatewayEnabled = true

        // Basic validation
        guard !self.manualGatewayHost.isEmpty else {
            withAnimation {
                self.connectError = "Host is required"
                self.connecting = false
            }
            return
        }

        await self.gatewayController.connectManual(
            host: self.manualGatewayHost,
            port: self.manualGatewayPort,
            useTLS: self.manualGatewayTLS)

        // Wait a beat for status update
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation {
            self.connecting = false
            if !self.isGatewayConnected {
                 self.connectError = self.appModel.gatewayStatusText
            }
        }
    }

    private func connectDiscovered(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        self.connectingGatewayID = gateway.id
        self.manualGatewayEnabled = false

        // Save preference
        GatewaySettingsStore.savePreferredGatewayStableID(gateway.stableID)
        GatewaySettingsStore.saveLastDiscoveredGatewayStableID(gateway.stableID)

        let err = await self.gatewayController.connectWithDiagnostics(gateway)

        await MainActor.run {
            self.connectingGatewayID = nil
            if let err {
                self.connectError = err
            }
        }
    }

    private func applySetupCode() {
        let raw = self.setupCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            self.setupStatusText = "Paste a setup code first."
            return
        }

        guard let payload = GatewaySetupCode.decode(raw: raw) else {
            self.setupStatusText = "Setup code not recognized."
            return
        }

        if let urlString = payload.url, let url = URL(string: urlString) {
            self.applySetupURL(url)
        } else if let host = payload.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.manualGatewayHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if let port = payload.port {
                self.manualGatewayPort = port
            } else {
                self.manualGatewayPort = 0
            }
            if let tls = payload.tls {
                self.manualGatewayTLS = tls
            }
        } else if let url = URL(string: raw), url.scheme != nil {
            self.applySetupURL(url)
        } else {
            self.setupStatusText = "Setup code missing URL or host."
            return
        }

        if let token = payload.token {
            self.gatewayToken = token
            self.saveCredentials(token: token, password: self.gatewayPassword)
        }
        if let password = payload.password {
            self.gatewayPassword = password
            self.saveCredentials(token: self.gatewayToken, password: password)
        }

        self.setupStatusText = "Setup code applied. You can now Connect."
    }

    private func applySetupURL(_ url: URL) {
        guard let host = url.host, !host.isEmpty else { return }
        self.manualGatewayHost = host
        if let port = url.port {
            self.manualGatewayPort = port
        } else {
            self.manualGatewayPort = 0
        }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "wss" || scheme == "https" {
            self.manualGatewayTLS = true
        } else if scheme == "ws" || scheme == "http" {
            self.manualGatewayTLS = false
        }
    }
}
