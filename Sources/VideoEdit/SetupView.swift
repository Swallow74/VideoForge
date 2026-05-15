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
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Setup iniziale").font(.title.bold())
            Text("Verifica delle dipendenze necessarie per il funzionamento")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isChecking {
                ProgressView("Controllo dipendenze...")
            } else {
                dependencyList
                actionButtons
            }
        }
        .padding(30)
        .frame(width: 520, height: 520)
        .task { await checkDeps() }
    }

    private var dependencyList: some View {
        VStack(spacing: 6) {
            ForEach(deps, id: \.name) { dep in
                HStack {
                    Image(systemName: dep.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(dep.installed ? .green : (dep.optional ? .orange : .red))
                        .font(.title3)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(dep.name).font(.body.bold())
                            if dep.optional {
                                Text("(opzionale)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let v = dep.version { Text(v).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if !dep.installed {
                        if installing == dep.name {
                            ProgressView().scaleEffect(0.7)
                        } else if !dep.optional {
                            Button("Installa") { install(dep) }
                                .buttonStyle(.borderedProminent)
                                .disabled(installing != nil)
                        } else {
                            Text("Skip").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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