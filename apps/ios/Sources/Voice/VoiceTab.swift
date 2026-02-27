import SwiftUI

struct VoiceTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VOICE")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .tracking(1)
                    Text("Voice mode")
                        .font(.title2.bold())
                }
                Spacer()
                StatusPill(
                    gateway: self.appModel.gatewayServerName != nil ? .connected : .disconnected,
                    voiceWakeEnabled: self.voiceWakeEnabled,
                    activity: nil)
            }
            .padding()
            .background(Color(red: 246/255, green: 247/255, blue: 250/255)) // Surface

            // Conversation Area (Placeholder for now as we don't have full history access in VoiceWakeManager)
            ScrollView {
                VStack(spacing: 20) {
                    if !self.voiceWakeEnabled && !self.talkEnabled {
                        Text("Enable Voice Wake or Talk Mode to start.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        Text("Tap the mic and speak.\nEach pause sends a turn automatically.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Color(red: 255/255, green: 255/255, blue: 255/255)) // White background

            // Bottom Controls
            VStack(spacing: 16) {
                // Status Text
                HStack(spacing: 6) {
                    Text(self.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 246/255, green: 247/255, blue: 250/255))
                        .clipShape(Capsule())
                }

                // Mic Button with Waveform
                ZStack {
                    if self.voiceWake.isListening || self.appModel.talkMode.isEnabled {
                        MicWaveformRing(level: self.voiceWake.inputLevel)
                            .frame(width: 120, height: 120)
                    }

                    Button {
                        self.toggleMic()
                    } label: {
                        Image(systemName: self.isMicActive ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(self.isMicActive ? Color.red : Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    }
                }
                .padding(.bottom, 20)

                Text(self.isMicActive ? "Tap to stop" : "Tap to speak")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.white)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
        }
        .background(Color(red: 246/255, green: 247/255, blue: 250/255))
    }

    private var isMicActive: Bool {
        self.voiceWakeEnabled || self.talkEnabled
    }

    private var statusText: String {
        if self.appModel.talkMode.isEnabled {
            return "Talk Mode Active"
        }
        if self.voiceWake.isListening {
            return "Listening..."
        }
        return "Mic off"
    }

    private func toggleMic() {
        let next = !self.isMicActive
        self.voiceWakeEnabled = next
        self.talkEnabled = next // Sync for simplicity in this UI
        self.appModel.setVoiceWakeEnabled(next)
        self.appModel.setTalkEnabled(next)
    }
}

struct MicWaveformRing: View {
    let level: Float
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                .scaleEffect(1 + CGFloat(level) * 0.5)
                .opacity(1 - Double(level))
        }
    }
}
