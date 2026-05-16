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
        VStack(spacing: 0) {
            headerSection

            Divider()

            if isChecking {
                Spacer()
                loadingState
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        dependencyList
                        if showInstallLog { installLogCard }
                    }
                    .padding(24)
                }

                Divider()
                footerSection
                    .padding(16)
            }
        }
        .frame(width: 620, height: 620)
        .background(.windowBackground)
        .task { await checkDeps() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Setup iniziale")
                    .font(.title2.weight(.semibold))
                Text("Verifica delle dipendenze necessarie")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Controllo dipendenze...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dependency List

    private var dependencyList: some View {
        VStack(spacing: 8) {
            ForEach(deps, id: \.name) { dep in
                HStack(spacing: 14) {
                    Image(systemName: dep.installed
                        ? "checkmark.circle.fill"
                        : (dep.optional ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                        .font(.title3)
                        .foregroundStyle(dep.installed
                            ? .green
                            : (dep.optional ? .orange : .red))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(dep.name)
                                .font(.body.weight(.medium))
                            if dep.optional {
                                Text("Opzionale")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.fill.tertiary)
                                    .clipShape(Capsule())
                            }
                        }
                        if let v = dep.version {
                            Text(v)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if !dep.installed {
                        if installing == dep.name {
                            ProgressView()
                                .controlSize(.small)
                        } else if !dep.optional {
                            Button {
                                install(dep)
                            } label: {
                                Label("Installa", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(installing != nil)
                        } else {
                            Text("Saltato")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(14)
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Install Log

    private var installLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Log installazione", systemImage: "terminal")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(installLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 80)
            .padding(10)
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if deps.contains(where: { !$0.installed && !$0.optional }) {
                Label("Completa le installazioni necessarie", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Tutte le dipendenze sono soddisfatte", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onComplete()
            } label: {
                Label("Continua", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(deps.contains { !$0.installed && !$0.optional })
        }
    }

    // MARK: - Logic

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
                case "mlx-whisper (venv)": try await DependencyService.installMLXWhisper()
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
