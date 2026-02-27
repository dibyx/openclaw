import OpenClawKit
import Network
import Observation
import os
import SwiftUI
import UIKit

struct SettingsTab: View {
    private struct FeatureHelp: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Environment(NodeAppModel.self) private var appModel: NodeAppModel
    @Environment(VoiceWakeManager.self) private var voiceWake: VoiceWakeManager
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController
    @Environment(\.dismiss) private var dismiss

    // Feature Toggles
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false
    @AppStorage("talk.background.enabled") private var talkBackgroundEnabled: Bool = false
    @AppStorage("camera.enabled") private var cameraEnabled: Bool = true
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("location.enabledMode") private var locationEnabledModeRaw: String = OpenClawLocationMode.off.rawValue

    // Device Info
    @AppStorage("node.displayName") private var displayName: String = "iOS Node"
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString

    @State private var defaultShareInstruction: String = ""
    @State private var activeFeatureHelp: FeatureHelp?
    @State private var lastLocationModeRaw: String = OpenClawLocationMode.off.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    self.featureToggle(
                        "Prevent Sleep",
                        isOn: self.$preventSleep,
                        help: "Keeps the screen awake while OpenClaw is open.")

                    TextField("Device Name", text: self.$displayName)
                }

                Section("Voice & Talk") {
                    self.featureToggle(
                        "Voice Wake",
                        isOn: self.$voiceWakeEnabled,
                        help: "Enables wake-word activation.") { newValue in
                            self.appModel.setVoiceWakeEnabled(newValue)
                        }

                    self.featureToggle(
                        "Talk Mode",
                        isOn: self.$talkEnabled,
                        help: "Enables voice conversation mode.") { newValue in
                            self.appModel.setTalkEnabled(newValue)
                        }

                    self.featureToggle(
                        "Background Listening",
                        isOn: self.$talkBackgroundEnabled,
                        help: "Keeps listening while backgrounded.")

                    NavigationLink("Wake Words") {
                        VoiceWakeWordsSettingsView()
                    }
                }

                Section("Permissions") {
                    self.featureToggle(
                        "Allow Camera",
                        isOn: self.$cameraEnabled,
                        help: "Allows the gateway to request photos/videos.")

                    Picker("Location Access", selection: self.$locationEnabledModeRaw) {
                        Text("Off").tag(OpenClawLocationMode.off.rawValue)
                        Text("While Using").tag(OpenClawLocationMode.whileUsing.rawValue)
                        Text("Always").tag(OpenClawLocationMode.always.rawValue)
                    }
                }

                Section("Share to Agent") {
                    TextField("Default Instruction", text: self.$defaultShareInstruction, axis: .vertical)
                        .lineLimit(2...4)
                    Text("Appended to content shared from other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: DeviceInfoHelper.openClawVersionString())
                    LabeledContent("Instance ID", value: self.instanceId)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .alert(item: self.$activeFeatureHelp) { help in
                Alert(
                    title: Text(help.title),
                    message: Text(help.message),
                    dismissButton: .default(Text("OK")))
            }
            .onAppear {
                self.defaultShareInstruction = ShareToAgentSettings.loadDefaultInstruction()
                self.lastLocationModeRaw = self.locationEnabledModeRaw
            }
            .onChange(of: self.defaultShareInstruction) { _, newValue in
                ShareToAgentSettings.saveDefaultInstruction(newValue)
            }
            .onChange(of: self.locationEnabledModeRaw) { _, newValue in
                let previous = self.lastLocationModeRaw
                self.lastLocationModeRaw = newValue
                guard let mode = OpenClawLocationMode(rawValue: newValue) else { return }
                Task {
                    let granted = await self.appModel.requestLocationPermissions(mode: mode)
                    if !granted {
                        await MainActor.run {
                            self.locationEnabledModeRaw = previous
                            self.lastLocationModeRaw = previous
                        }
                        return
                    }
                    await MainActor.run {
                        self.gatewayController.refreshActiveGatewayRegistrationFromSettings()
                    }
                }
            }
        }
    }

    private func featureToggle(
        _ title: String,
        isOn: Binding<Bool>,
        help: String,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Button {
                self.activeFeatureHelp = FeatureHelp(title: title, message: help)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: isOn.wrappedValue) { _, newValue in
            onChange?(newValue)
        }
    }
}
