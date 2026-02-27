import OpenClawChatUI
import OpenClawKit
import SwiftUI

struct ChatTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var viewModel: OpenClawChatViewModel?
    private let userAccent = Color(red: 29/255, green: 93/255, blue: 216/255)

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    OpenClawChatView(
                        viewModel: viewModel,
                        showsSessionSwitcher: true,
                        userAccent: self.userAccent)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(self.chatTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            self.setupViewModel()
        }
        .onChange(of: self.appModel.chatSessionKey) { _, _ in
            self.setupViewModel()
        }
    }

    private func setupViewModel() {
        let gateway = self.appModel.operatorSession
        let transport = IOSGatewayChatTransport(gateway: gateway)
        self.viewModel = OpenClawChatViewModel(
            sessionKey: self.appModel.chatSessionKey,
            transport: transport)
    }

    private var chatTitle: String {
        let trimmed = (self.appModel.activeAgentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Chat" }
        return "Chat (\(trimmed))"
    }
}
