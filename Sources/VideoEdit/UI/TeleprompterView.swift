import SwiftUI

struct TeleprompterView: View {
    @Bindable var service: TeleprompterService
    @State private var playbackTask: Task<Void, Never>? = nil
    @State private var wordIndex: Int = 0
    @State private var words: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(16)

            Divider()

            scriptArea
                .frame(maxHeight: .infinity)

            Divider()

            controlBar
                .padding(16)
        }
        .background(.windowBackground)
        .onAppear {
            words = service.text.split(separator: " ").map(String.init)
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "scroll")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Teleprompter")
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            if !words.isEmpty {
                Text("\(wordIndex) / \(words.count) parole")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ColorPicker("Testo", selection: $service.textColor)
                    .controlSize(.small)
                    .help("Colore testo")
                ColorPicker("Sfondo", selection: $service.backgroundColor)
                    .controlSize(.small)
                    .help("Colore sfondo")
            }
        }
    }

    // MARK: - Script Area

    private var scriptArea: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    service.backgroundColor.opacity(service.opacity)
                        .overlay(
                            LinearGradient(
                                stops: [
                                    .init(color: service.backgroundColor.opacity(service.opacity), location: 0),
                                    .init(color: .clear, location: 0.05),
                                    .init(color: .clear, location: 0.85),
                                    .init(color: service.backgroundColor.opacity(service.opacity), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text(service.text)
                        .font(.system(size: CGFloat(service.fontSize)))
                        .foregroundColor(service.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, geo.size.height * 0.25)
                        .id("text-top")
                        .offset(y: -CGFloat(service.scrollOffset) * (geo.size.height * 4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: service.scrollOffset) { _, newOffset in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("text-top", anchor: .top)
                }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 12) {
            // Playback controls
            HStack(spacing: 10) {
                Button {
                    stopPlayback()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!service.isPlaying && wordIndex == 0)

                Button {
                    togglePlayback()
                } label: {
                    Label(
                        service.isPlaying ? "Pausa" : "Riproduci",
                        systemImage: service.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()

                // Speed control
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "tortoise")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Slider(value: $service.speed, in: 30...200, step: 5)
                            .frame(width: 160)
                        Image(systemName: "hare")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(Int(service.speed)) parole/min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // Font size + opacity
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Slider(value: $service.fontSize, in: 16...72, step: 2)
                        .frame(width: 120)
                    Text("\(Int(service.fontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44)
                }

                Divider()
                    .frame(height: 20)

                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Slider(value: $service.opacity, in: 0.3...1.0)
                        .frame(width: 80)
                    Text("\(Int(service.opacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                }
            }
        }
    }

    // MARK: - Playback Logic

    private func togglePlayback() {
        if service.isPlaying {
            playbackTask?.cancel()
            playbackTask = nil
            service.isPlaying = false
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard !words.isEmpty else { return }
        if wordIndex >= words.count { wordIndex = 0 }
        service.isPlaying = true

        let intervalNs = UInt64((60.0 / service.speed) * 1_000_000_000)

        playbackTask = Task { @MainActor in
            while wordIndex < words.count && !Task.isCancelled {
                wordIndex += 1
                service.scrollOffset = Double(wordIndex) / Double(words.count)
                try? await Task.sleep(nanoseconds: intervalNs)
            }
            if wordIndex >= words.count {
                service.isPlaying = false
            }
            playbackTask = nil
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        service.isPlaying = false
        wordIndex = 0
        service.scrollOffset = 0
    }
}

#Preview {
    TeleprompterView(service: {
        let s = TeleprompterService()
        s.loadScript("Questo è un esempio di testo per il teleprompter. Puoi scrivere qui il tuo copione e regolare la velocità di scorrimento.")
        return s
    }())
    .frame(width: 700, height: 500)
}