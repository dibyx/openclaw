import SwiftUI

struct RootTabs: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: self.$selectedTab) {
            ConnectTab()
                .tabItem {
                    Label("Connect", systemImage: "checkmark.circle")
                }
                .tag(0)

            ChatTab()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(1)

            VoiceTab()
                .tabItem {
                    Label("Voice", systemImage: "mic")
                }
                .tag(2)

            ScreenTab()
                .tabItem {
                    Label("Screen", systemImage: "rectangle.dashed.and.paperclip")
                }
                .tag(3)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
        .accentColor(Color.openClawAccent)
    }
}
