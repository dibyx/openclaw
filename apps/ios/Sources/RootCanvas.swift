import SwiftUI
import UIKit

struct RootCanvas: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    // Global Settings
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("canvas.debugStatusEnabled") private var canvasDebugStatusEnabled: Bool = false

    // Onboarding
    @AppStorage("onboarding.requestID") private var onboardingRequestID: Int = 0
    @AppStorage("gateway.onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("gateway.hasConnectedOnce") private var hasConnectedOnce: Bool = false
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("onboarding.quickSetupDismissed") private var quickSetupDismissed: Bool = false

    @State private var showOnboarding: Bool = false
    @State private var onboardingAllowSkip: Bool = true
    @State private var didEvaluateOnboarding: Bool = false
    @State private var didAutoOpenSettings: Bool = false
    @State private var showQuickSetup: Bool = false

    // Toast state
    @State private var voiceWakeToastText: String?
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Main App Navigation
            RootTabs()
                .preferredColorScheme(.dark) // Fixed: Enforce dark mode for status bar legibility

            // Global Overlays
            if self.appModel.cameraFlashNonce != 0 {
                CameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
            }

            if self.appModel.talkMode.isEnabled {
                TalkOrbOverlay()
                    .transition(.opacity)
            }

            // Voice Wake Feedback
            if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                VoiceWakeToast(
                    command: voiceWakeToastText,
                    brighten: false) // Fixed: Dark theme means we don't brighten for contrast
                    .padding(.leading, 10)
                    .safeAreaPadding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .gatewayTrustPromptAlert()
        .deepLinkAgentPromptAlert()
        .fullScreenCover(isPresented: self.$showOnboarding) {
            OnboardingWizardView(
                allowSkip: self.onboardingAllowSkip,
                onClose: {
                    self.showOnboarding = false
                })
                .environment(self.appModel)
                .environment(self.appModel.voiceWake)
                .environment(self.gatewayController)
        }
        .sheet(isPresented: self.$showQuickSetup) {
            GatewayQuickSetupSheet()
                .environment(self.appModel)
                .environment(self.gatewayController)
        }
        .onAppear { self.updateIdleTimer() }
        .onAppear { self.evaluateOnboardingPresentation(force: false) }
        .onChange(of: self.preventSleep) { _, _ in self.updateIdleTimer() }
        .onChange(of: self.scenePhase) { _, _ in self.updateIdleTimer() }
        .onAppear { self.maybeShowQuickSetup() }
        .onChange(of: self.gatewayController.gateways.count) { _, _ in self.maybeShowQuickSetup() }
        .onAppear { self.updateCanvasDebugStatus() }
        .onChange(of: self.canvasDebugStatusEnabled) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayStatusText) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayServerName) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayServerName) { _, newValue in
            if newValue != nil {
                self.showOnboarding = false
                self.onboardingComplete = true
                self.hasConnectedOnce = true
                OnboardingStateStore.markCompleted(mode: nil)
            }
        }
        .onChange(of: self.onboardingRequestID) { _, _ in
            self.evaluateOnboardingPresentation(force: true)
        }
        .onChange(of: self.appModel.gatewayRemoteAddress) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.voiceWake.lastTriggeredCommand) { _, newValue in
            guard let newValue else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            self.toastDismissTask?.cancel()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.voiceWakeToastText = trimmed
            }

            self.toastDismissTask = Task {
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.voiceWakeToastText = nil
                    }
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            self.toastDismissTask?.cancel()
            self.toastDismissTask = nil
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (self.scenePhase == .active && self.preventSleep)
    }

    private func updateCanvasDebugStatus() {
        self.appModel.screen.setDebugStatusEnabled(self.canvasDebugStatusEnabled)
        guard self.canvasDebugStatusEnabled else { return }
        let title = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = self.appModel.gatewayServerName ?? self.appModel.gatewayRemoteAddress
        self.appModel.screen.updateDebugStatus(title: title, subtitle: subtitle)
    }

    private func evaluateOnboardingPresentation(force: Bool) {
        if force {
            self.onboardingAllowSkip = true
            self.showOnboarding = true
            return
        }

        guard !self.didEvaluateOnboarding else { return }
        self.didEvaluateOnboarding = true

        let route = Self.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: OnboardingStateStore.shouldPresentOnLaunch(appModel: self.appModel))

        if route == .onboarding {
            self.onboardingAllowSkip = true
            self.showOnboarding = true
        }
    }

    private func hasExistingGatewayConfig() -> Bool {
        if GatewaySettingsStore.loadLastGatewayConnection() != nil { return true }
        let manualHost = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.manualGatewayEnabled && !manualHost.isEmpty
    }

    private func maybeShowQuickSetup() {
        guard !self.quickSetupDismissed else { return }
        guard !self.showOnboarding else { return }
        guard !self.showQuickSetup else { return }
        guard self.appModel.gatewayServerName == nil else { return }
        guard !self.gatewayController.gateways.isEmpty else { return }
        self.showQuickSetup = true
    }

    // Helper enum for logic reuse
    enum StartupPresentationRoute: Equatable {
        case none
        case onboarding
        case settings // Kept for logic compatibility, though settings isn't auto-opened now
    }

    static func startupPresentationRoute(
        gatewayConnected: Bool,
        hasConnectedOnce: Bool,
        onboardingComplete: Bool,
        hasExistingGatewayConfig: Bool,
        shouldPresentOnLaunch: Bool) -> StartupPresentationRoute
    {
        if gatewayConnected { return .none }
        if shouldPresentOnLaunch || !hasConnectedOnce || !onboardingComplete { return .onboarding }
        if !hasExistingGatewayConfig { return .settings }
        return .none
    }
}

private struct CameraFlashOverlay: View {
    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                self.task?.cancel()
                self.task = Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.opacity = 0.85
                    }
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    withAnimation(.easeOut(duration: 0.32)) {
                        self.opacity = 0
                    }
                }
            }
    }
}
