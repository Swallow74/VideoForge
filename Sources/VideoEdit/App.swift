import SwiftUI

@main
struct VideoForgeApp: App {
    @State private var pipelineService = PipelineService()
    @State private var showSetup = !UserDefaults.standard.bool(forKey: "setup_complete")

    var body: some Scene {
        WindowGroup {
            if showSetup {
                SetupView {
                    UserDefaults.standard.set(true, forKey: "setup_complete")
                    showSetup = false
                }
            } else {
                ContentView()
                    .environment(pipelineService)
                    .task { await pipelineService.refreshAPIModels() }
            }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 800)
        .defaultPosition(.center)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(pipelineService)
        }
        #endif
    }
}
