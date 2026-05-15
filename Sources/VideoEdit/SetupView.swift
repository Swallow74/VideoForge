import SwiftUI

struct SetupView: View {
    @State private var deps: [DependencyStatus] = []
    @State private var isChecking = true
    @State private var installing: String? = nil
    @State private var installLog = ""
    @State private var showInstallLog = false
    @State private var setupComplete = false

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Setup iniziale").font(.largeTitle.bold())
            Text("Verifica delle dipendenze necessarie per il funzionamento")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isChecking {
                ProgressView("Controllo dipendenze...")
                    .controlSize(.large)
            } else {
                dependencyList
                actionButtons
            }
        }
        .padding(40)
        .frame(width: 640, height: 640)
        .task { await checkDeps() }
    }

    private var dependencyList: some View {
        VStack(spacing: 8) {
            ForEach(deps, id: \.name) { dep in
                HStack(spacing: 12) {
                    Image(systemName: dep.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(dep.installed ? .green : (dep.optional ? .orange : .red))
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(dep.name).font(.body.bold())
                            if dep.optional {
                                Text("(opzionale)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let v = dep.version { Text(v).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if !dep.installed {
                        if installing == dep.name {
                            ProgressView().scaleEffect(0.8).controlSize(.small)
                        } else if !dep.optional {
                            Button("Installa") { install(dep) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(installing != nil)
                        } else {
                            Text("Skip").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            if showInstallLog {
                ScrollView {
                    Text(installLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 80)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button("Continua") { onComplete() }
                .buttonStyle(.borderedProminent)
                .disabled(deps.contains { !$0.installed && !$0.optional })
        }
    }

    private func checkDeps() async {
        isChecking = true
        deps = DependencyService.checkAll()
        isChecking = false
    }

    private func install(_ dep: DependencyStatus) {
        installing = dep.name
        installLog = ""

        Task {
            do {
                switch dep.name {
                case "ffmpeg": try await DependencyService.installFFmpeg()
                case "Python 3": try await DependencyService.installPython()
                case "mlx-whisper": try await DependencyService.installMLXWhisper()
                default: break
                }
                installLog += "✓ Installazione completata\n"
                await checkDeps()
            } catch {
                installLog += "✗ Errore: \(error.localizedDescription)\n"
            }
            showInstallLog = true
            installing = nil
        }
    }
}