import OpenClawKit
import SwiftUI

struct ScreenTab: View {
    @Environment(NodeAppModel.self) private var appModel

    var body: some View {
        ZStack(alignment: .top) {
            ScreenWebView(controller: self.appModel.screen)
                .ignoresSafeArea()

            if self.appModel.gatewayServerName == nil {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "rectangle.dashed.and.paperclip")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.openClawSecondaryText)
                    Text("Canvas Disconnected")
                        .font(.headline)
                        .foregroundStyle(Color.openClawSecondaryText)

                    if let errorText = self.appModel.screen.errorText {
                        Text(errorText)
                            .font(.caption)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.openClawBackground)
            } else if self.shouldShowRestore {
                VStack {
                    Button {
                        self.appModel.screen.reload()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Restore dashboard")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.openClawText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Material.thin)
                        .clipShape(Capsule())
                        .shadow(radius: 2)
                    }
                    .padding(.top, 60) // Push down from safe area
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var shouldShowRestore: Bool {
        return true
    }
}
