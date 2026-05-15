import SwiftUI

struct TeleprompterView: View {
    @Bindable var service: TeleprompterService
    @State private var timer: Timer? = nil

    var body: some View {
        VStack(spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(service.text)
                        .font(.system(size: CGFloat(service.fontSize)))
                        .foregroundColor(service.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .id("text-top")
                }
                .background(service.backgroundColor.opacity(service.opacity))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 250, maxHeight: .infinity)
                .onChange(of: service.scrollOffset) { _, _ in
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("text-top", anchor: .top)
                    }
                }
            }

            HStack {
                Button(service.isPlaying ? "⏸  Pausa" : "▶  Riproduci") {
                    togglePlayback()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("⏹  Stop") {
                    stopPlayback()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Velocità: \(Int(service.speed)) WPM")
                        .font(.body)
                    Slider(value: $service.speed, in: 30...200, step: 5)
                        .frame(width: 180)
                }
            }

            HStack(spacing: 16) {
                ColorPicker("Testo", selection: $service.textColor)
                    .controlSize(.large)
                ColorPicker("Sfondo", selection: $service.backgroundColor)
                    .controlSize(.large)
                Spacer()
                Slider(value: $service.opacity, in: 0.3...1.0)
                    .frame(width: 120)
                Text("\(Int(service.opacity * 100))%")
                    .font(.body.monospacedDigit())
                    .frame(width: 48)
            }
        }
        .padding(20)
    }

    private func togglePlayback() {
        if service.isPlaying {
            timer?.invalidate()
            timer = nil
            service.isPlaying = false
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        service.isPlaying = true
        let wordsPerTick = service.speed / 60 / 10  // tick every 0.1s
        var wordIndex = 0
        let words = service.text.split(separator: " ")

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard wordIndex < words.count else {
                self.timer?.invalidate()
                self.timer = nil
                service.isPlaying = false
                return
            }
            wordIndex += 1
            service.scrollOffset = Double(wordIndex) / Double(words.count)
        }
    }

    private func stopPlayback() {
        timer?.invalidate()
        timer = nil
        service.isPlaying = false
        service.scrollOffset = 0
    }
}

#Preview {
    TeleprompterView(service: {
        let s = TeleprompterService()
        s.loadScript("Questo è un esempio di testo per il teleprompter. Puoi scrivere qui il tuo copione e regolare la velocità di scorrimento.")
        return s
    }())
    .frame(width: 600, height: 400)
}