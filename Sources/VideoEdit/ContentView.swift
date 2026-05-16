import SwiftUI
import UniformTypeIdentifiers
import VideoEditCore

struct ContentView: View {
    @Environment(PipelineService.self) private var pipeline
    @State private var showTeleprompter = false
    @State private var showAdvanced = false
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    FilesCard(pipeline: pipeline, isDropTarget: $isDropTarget)
                    TranscriptionCard(pipeline: pipeline)
                    ProcessingCard(
                        pipeline: pipeline,
                        showAdvanced: $showAdvanced
                    )
                    if showAdvanced { AdvancedCard() }
                    ProgressBar(pipeline: pipeline)
                }
                .padding(20)
            }

            Divider()

            LogCard(pipeline: pipeline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .padding(.bottom, 12)
        .frame(minWidth: 1000, minHeight: 800)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showTeleprompter) {
            TeleprompterView(service: pipeline.teleprompterService)
                .frame(minWidth: 640, minHeight: 520)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if pipeline.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                showTeleprompter = true
            } label: {
                Label("Teleprompter", systemImage: "scroll")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button {
                if pipeline.isProcessing {
                    pipeline.cancel()
                } else {
                    pipeline.start()
                }
            } label: {
                Label(
                    pipeline.isProcessing ? "Stop" : "Avvia",
                    systemImage: pipeline.isProcessing ? "stop.fill" : "play.fill"
                )
            }
            .disabled(pipeline.files.isEmpty && !pipeline.isProcessing)
            .keyboardShortcut(pipeline.isProcessing ? "." : "r", modifiers: .command)
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}

// MARK: - Files Card

private struct FilesCard: View {
    let pipeline: PipelineService
    @Binding var isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "File", icon: "folder")

            HStack(spacing: 10) {
                Button {
                    pipeline.addFiles()
                } label: {
                    Label("Aggiungi file", systemImage: "plus")
                }
                .disabled(pipeline.isProcessing)
                .controlSize(.large)

                Button {
                    pipeline.files.removeAll()
                } label: {
                    Label("Rimuovi tutti", systemImage: "trash")
                }
                .disabled(pipeline.files.isEmpty || pipeline.isProcessing)
                .controlSize(.large)
                .tint(.secondary)

                Spacer()

                Text("\(pipeline.files.count) file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if pipeline.files.isEmpty {
                emptyDropZone
            } else {
                fileList
            }
        }
        .padding(20)
        .background(.fill.quinary)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.tint, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop)
    }

    private var emptyDropZone: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Aggiungi file video o audio")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                if isDropTarget {
                    Text("Rilascia per aggiungere")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .transition(.opacity)
                } else {
                    Text("Oppure trascina i file qui")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 24)
            .animation(.easeInOut(duration: 0.2), value: isDropTarget)
            Spacer()
        }
    }

    private var fileList: some View {
        List(Array(pipeline.files.enumerated()), id: \.offset) { i, file in
            HStack(spacing: 10) {
                Image(systemName: AudioService.isAudioFile(file) ? "waveform" : "film")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .font(.body)
                Spacer()
            }
            .swipeActions {
                Button("Rimuovi", role: .destructive) {
                    pipeline.files.remove(at: i)
                }
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(minHeight: 80)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !pipeline.isProcessing else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                if let url = (item as? NSURL)?.absoluteURL {
                    Task { @MainActor in
                        if !pipeline.files.contains(url) {
                            pipeline.files.append(url)
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Transcription Card

private struct TranscriptionCard: View {
    let pipeline: PipelineService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Trascrizione", icon: "text.bubble")

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Label("Modello", systemImage: "cpu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).asrModel) {
                        ForEach(PipelineService.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .controlSize(.large)

                    Spacer()

                    Label("Lingua", systemImage: "textformat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).language) {
                        ForEach(["it", "en", "fr", "de", "es", "pt", "ja", "zh", "auto"], id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .controlSize(.large)
                }

                Divider()

                HStack(spacing: 16) {
                    Label("Correzione", systemImage: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).textModel) {
                        Text("Nessuna").tag("")
                        ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .controlSize(.large)

                    Spacer()

                    Label("Profilo", systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).profileName) {
                        Text("Auto").tag("auto")
                        Text("Conversational").tag(ProfileName.conversational.rawValue)
                        Text("Lecturing").tag(ProfileName.lecturing.rawValue)
                        Text("Technical").tag(ProfileName.technical.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .controlSize(.large)
                }

                Divider()

                HStack(spacing: 16) {
                    Label("API URL", systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    TextField("http://127.0.0.1:8000", text: Bindable(pipeline).apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                    Button {
                        Task { await pipeline.refreshAPIModels() }
                    } label: {
                        Label("Aggiorna", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Rileva modelli disponibili dall'API")
                }
            }
        }
        .padding(20)
        .background(.fill.quinary)
        .clipShape(.rect(cornerRadius: 14))
    }
}

// MARK: - Processing Card

private struct ProcessingCard: View {
    let pipeline: PipelineService
    @Binding var showAdvanced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Elaborazione", icon: "slider.horizontal.3")

            VStack(spacing: 12) {
                Toggle(isOn: Bindable(pipeline).enableSilenceRemoval) {
                    Label("Rimuovi silenzi", systemImage: "waveform.path.ecg")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enableSilenceRemoval {
                    silenceSettings
                }

                Toggle(isOn: Bindable(pipeline).enableNoiseRemoval) {
                    Label("Rimuovi rumore fondo", systemImage: "speaker.wave.2")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enableNoiseRemoval {
                    noiseSettings
                }

                Toggle(isOn: Bindable(pipeline).enablePortraitBox) {
                    Label("Portrait Box 9:16", systemImage: "rectangle.ratio.9.to.16")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enablePortraitBox {
                    portraitSettings
                }

                Toggle(isOn: Bindable(pipeline).enableOverlay) {
                    Label("Overlay PIP", systemImage: "rectangle.on.rectangle")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enableOverlay {
                    overlaySettings
                }

                Toggle(isOn: Bindable(pipeline).enableMusicDucking) {
                    Label("Musica + Auto-Ducking", systemImage: "music.note")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enableMusicDucking {
                    musicSettings
                }

                Toggle(isOn: Bindable(pipeline).enableDualLanguage) {
                    Label("Sottotitoli bilingue", systemImage: "globe")
                        .font(.body)
                }
                .toggleStyle(.switch)
                if pipeline.enableDualLanguage {
                    languageSettings
                }

                if !pipeline.files.isEmpty {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdvanced.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                .font(.caption)
                            Text(showAdvanced ? "Nascondi avanzate" : "Mostra avanzate")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(.fill.quinary)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var silenceSettings: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("Soglia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Slider(value: Bindable(pipeline).silenceThreshold, in: -50...(-10), step: 5)
                Text("\(Int(pipeline.silenceThreshold)) dB")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56)
            }
            HStack(spacing: 12) {
                Text("Durata min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Slider(value: Bindable(pipeline).minSilenceDuration, in: 0.1...2.0, step: 0.1)
                Text("\(pipeline.minSilenceDuration, specifier: "%.1f") s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56)
            }
        }
        .padding(.leading, 28)
    }

    private var noiseSettings: some View {
        HStack(spacing: 12) {
            Text("Forza")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: Bindable(pipeline).noiseStrength, in: 0.1...1.0, step: 0.1)
            Text("\(pipeline.noiseStrength, specifier: "%.1f")")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56)
        }
        .padding(.leading, 28)
    }

    private var portraitSettings: some View {
        HStack(spacing: 12) {
            Text("Ritaglio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Picker("", selection: Bindable(pipeline).portraitCropMode) {
                ForEach(["Center", "Top", "Bottom", "Smart"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .controlSize(.large)
            .padding(.leading, 28)
            Toggle("Sfondo sfocato", isOn: Bindable(pipeline).portraitBlurBackground)
                .toggleStyle(.switch)
                .font(.subheadline)
        }
    }

    private var overlaySettings: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    pipeline.addOverlayVideo()
                } label: {
                    Label("Scegli video", systemImage: "plus.square")
                }
                .controlSize(.large)
                if let ov = pipeline.overlayVideoURL {
                    Text(ov.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 28)

            HStack(spacing: 12) {
                Text("Posizione:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: Bindable(pipeline).overlayPosition) {
                    ForEach(["Top Left", "Top Right", "Bottom Left", "Bottom Right"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.large)
                Spacer()
                Text("Scala:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: Bindable(pipeline).overlayScale, in: 0.1...0.5)
                    .frame(width: 100)
                Text("\(pipeline.overlayScale, specifier: "%.2f")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .padding(.leading, 28)
        }
    }

    private var musicSettings: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    pipeline.addMusicFile()
                } label: {
                    Label("Scegli musica", systemImage: "plus.square")
                }
                .controlSize(.large)
                if let m = pipeline.musicURL {
                    Text(m.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 28)

            HStack(spacing: 12) {
                    Text("Volume")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Slider(value: Bindable(pipeline).musicVolume, in: 0.0...1.0, step: 0.05)
                    Text("\(pipeline.musicVolume, specifier: "%.2f")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48)
                }
                .padding(.leading, 28)

            HStack(spacing: 12) {
                    Text("Duck")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Slider(value: Bindable(pipeline).duckLevel, in: 0.0...1.0, step: 0.05)
                    Text("\(pipeline.duckLevel, specifier: "%.2f")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48)
                }
                .padding(.leading, 28)
        }
    }

    private var languageSettings: some View {
        HStack(spacing: 12) {
            Text("Seconda lingua:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Picker("", selection: Bindable(pipeline).secondaryLanguage) {
                ForEach(["en", "fr", "de", "es", "pt"], id: \.self) { Text($0.uppercased()).tag($0) }
            }
            .labelsHidden()
            .controlSize(.large)
            Spacer()
            Text("Traduzione:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("", selection: Bindable(pipeline).translationModel) {
                Text("Stesso modello").tag("")
                ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .controlSize(.large)
        }
        .padding(.leading, 28)
    }
}

// MARK: - Advanced Card

private struct AdvancedCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Opzioni avanzate", icon: "gearshape.2")

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Label("Output SRT personalizzato", systemImage: "doc.text")
                        .font(.body)
                    Spacer()
                    Text("In sviluppo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Label("Batch concurrente", systemImage: "square.stack.3d.up")
                        .font(.body)
                    Spacer()
                    Text("In sviluppo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .background(.fill.quinary)
        .clipShape(.rect(cornerRadius: 14))
    }
}

// MARK: - Progress Bar

private struct ProgressBar: View {
    let pipeline: PipelineService

    var body: some View {
        VStack(spacing: 6) {
            if !pipeline.statusText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(pipeline.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(pipeline.progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: pipeline.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
    }
}

// MARK: - Log Card

private struct LogCard: View {
    let pipeline: PipelineService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text("Log")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !pipeline.log.isEmpty {
                    Button("Pulisci") {
                        pipeline.log = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(pipeline.log.isEmpty ? "Nessun log disponibile" : pipeline.log)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(pipeline.log.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("log-bottom")
                }
                .frame(minHeight: 120, maxHeight: 200)
                .padding(12)
                .background(.fill.quinary)
                .clipShape(.rect(cornerRadius: 10))
                .onChange(of: pipeline.log) { _, _ in
                    withAnimation(.default) {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(PipelineService())
        .frame(width: 900, height: 900)
}
