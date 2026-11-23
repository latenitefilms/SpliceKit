import SwiftUI
import AppKit

@MainActor
private final class SpliceKitSession: ObservableObject {
    enum Access {
        case checking
        case requiresApp(checkingAgain: Bool)
        case ready(PatcherModel)
    }

    @Published private(set) var access: Access = .checking

    init() {
        checkEligibility()
    }

    func checkAgain() {
        guard case .requiresApp(checkingAgain: false) = access else { return }
        access = .requiresApp(checkingAgain: true)
        checkEligibility()
    }

    private func checkEligibility() {
        Task {
            guard await LateNiteAppValidator.hasEligibleAppInstalled() else {
                access = .requiresApp(checkingAgain: false)
                return
            }

            access = .ready(PatcherModel())
        }
    }
}

// MARK: - App Entry Point

@main
struct SpliceKitApp: App {
    private static let helpURL = URL(string: "https://splicekit.fcp.cafe/installation/")!
    private static let releasesURL = URL(string: "https://github.com/latenitefilms/SpliceKit/releases")!
    @StateObject private var session = SpliceKitSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WizardView {
                withPatcher { PatcherPanels(model: $0) }
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.checkAgain() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("View Releases on GitHub") {
                    NSWorkspace.shared.open(Self.releasesURL)
                }
            }

            CommandGroup(replacing: .help) {
                Button("SpliceKit Help") {
                    NSWorkspace.shared.open(Self.helpURL)
                }
            }
        }

        Window("Logs", id: "log-panel") {
            withPatcher { LogPanelView(model: $0) }
        }
        .defaultSize(width: 600, height: 400)
    }

    @ViewBuilder
    private func withPatcher<Content: View>(@ViewBuilder content: (PatcherModel) -> Content) -> some View {
        switch session.access {
        case .checking:
            ProgressView("Checking for a LateNite app…")
                .padding(24)
        case .requiresApp(let checkingAgain):
            LateNiteAccessPanel(isChecking: checkingAgain, checkAgain: session.checkAgain)
        case .ready(let model):
            content(model)
        }
    }
}
