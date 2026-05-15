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
                    .frame(minWidth: 1000, minHeight: 800)
                    .task { await pipelineService.refreshAPIModels() }
            }
        }
        .windowResizability(.contentMinSize)
    }
}