import SwiftUI

struct LateNiteAccessPanel: View {
    let isChecking: Bool
    let checkAgain: () -> Void

    private static let storeURL = URL(string: "https://apps.apple.com/au/developer/latenite-films-pty-ltd/id1652018641")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unlock SpliceKit")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Install one of these paid LateNite apps from the Mac App Store to use the patcher. If you already own one, you can download it again from your purchases.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    GroupBox {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(LateNiteAppValidator.eligibleApps, id: \.bundleID) { app in
                                Text(app.name)
                            }
                        }
                        .padding(8)
                    } label: {
                        Text("Eligible apps")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack(spacing: 12) {
                Group {
                    if isChecking {
                        Label {
                            Text("Checking this Mac…")
                        } icon: {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Label("No eligible app found", systemImage: "info.circle")
                    }
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Check Again", action: checkAgain)
                    .disabled(isChecking)
                Link("Open Mac App Store", destination: Self.storeURL)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 300)
    }
}

#Preview("LateNite app required") {
    WizardView {
        LateNiteAccessPanel(isChecking: false, checkAgain: {})
    }
}
