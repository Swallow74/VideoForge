import SwiftUI
import UniformTypeIdentifiers
import VideoEditCore

struct ContentView: View {
    @Environment(PipelineService.self) private var pipeline
    @State private var showTeleprompter = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            headerView.padding(.horizontal).padding(.top, 12)
            Divider().padding(.vertical, 6)

            ScrollView {
                VStack(spacing: 8) {
                    filesSection
                    transcriptionSection
                    audioCleanupSection
                    videoSection
                    advancedSection
                    progressSection
                }
                .padding(.horizontal)
            }

            Divider().padding(.vertical, 6)
            logSection.padding(.horizontal)
        }
        .padding(.bottom, 12)
        .sheet(isPresented: $showTeleprompter) {
            TeleprompterView(service: pipeline.teleprompterService)
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("VideoForge").font(.title2.bold())
            Spacer()
            if pipeline.isProcessing { ProgressView().scaleEffect(0.8).padding(.trailing, 4) }
            Button("📜 Teleprompter") { showTeleprompter = true }
                .buttonStyle(.bordered)
            Button(pipeline.isProcessing ? "Stop" : "▶ Avvia") {
                pipeline.isProcessing ? pipeline.cancel() : pipeline.start()
            }
            .disabled(pipeline.files.isEmpty && !pipeline.isProcessing)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        GroupBox("File") {
            VStack(spacing: 6) {
                HStack {
                    Button("+ Aggiungi file") { pipeline.addFiles() }.disabled(pipeline.isProcessing)
                    Button("✕ Rimuovi tutti") { pipeline.files.removeAll() }.disabled(pipeline.files.isEmpty)
                    Spacer()
                    Text("\(pipeline.files.count) file").foregroundStyle(.secondary).font(.caption)
                }
                List(Array(pipeline.files.enumerated()), id: \.offset) { i, file in
                    HStack {
                        Image(systemName: AudioService.isAudioFile(file) ? "waveform" : "film").foregroundStyle(.secondary)
                        Text(file.lastPathComponent).lineLimit(1)
                        Spacer()
                    }
                    .swipeActions { Button("Rimuovi", role: .destructive) { pipeline.files.remove(at: i) } }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true)).frame(minHeight: 80)
            }
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        GroupBox("Trascrizione") {
            VStack(spacing: 8) {
                HStack {
                    Text("Modello:").frame(width: 100, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).asrModel) {
                        ForEach(PipelineService.availableModels, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 140)
                    Text("Lingua:").frame(width: 50)
                    Picker("", selection: Bindable(pipeline).language) {
                        ForEach(["it", "en", "fr", "de", "es", "pt", "ja", "zh", "auto"], id: \.self) { Text($0.uppercased()).tag($0) }
                    }.labelsHidden().frame(width: 70)
                }
                HStack {
                    Text("Correzione:").frame(width: 100, alignment: .leading)
                    Picker("", selection: Bindable(pipeline).textModel) {
                        Text("(nessuno)").tag("")
                        ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 180)
                    Text("Profilo:").frame(width: 50)
                    Picker("", selection: Bindable(pipeline).profileName) {
                        Text("Auto").tag("auto")
                        Text("Conversational").tag(ProfileName.conversational.rawValue)
                        Text("Lecturing").tag(ProfileName.lecturing.rawValue)
                        Text("Technical").tag(ProfileName.technical.rawValue)
                    }.labelsHidden().frame(width: 130)
                }
                HStack {
                    Text("API URL:").frame(width: 100, alignment: .leading)
                    TextField("http://127.0.0.1:8000", text: Bindable(pipeline).apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Button("↻") {
                        Task { await pipeline.refreshAPIModels() }
                    }
                    .buttonStyle(.bordered)
                    .help("Rileva modelli disponibili dall'API")
                }
            }
        }
    }

    // MARK: - Audio Cleanup

    private var audioCleanupSection: some View {
        GroupBox("Pulizia Audio") {
            VStack(spacing: 8) {
                Toggle("Rimuovi silenzi", isOn: Bindable(pipeline).enableSilenceRemoval)
                if pipeline.enableSilenceRemoval {
                    HStack {
                        Text("Soglia silenzio:").frame(width: 120)
                        Slider(value: Bindable(pipeline).silenceThreshold, in: -50...(-10), step: 5)
                        Text("\(Int(pipeline.silenceThreshold)) dB").frame(width: 60)
                    }
                    HStack {
                        Text("Durata min:").frame(width: 120)
                        Slider(value: Bindable(pipeline).minSilenceDuration, in: 0.1...2.0, step: 0.1)
                        Text("\(pipeline.minSilenceDuration, specifier: "%.1f") s").frame(width: 60)
                    }
                }

                Toggle("Rimuovi rumore fondo", isOn: Bindable(pipeline).enableNoiseRemoval)
                if pipeline.enableNoiseRemoval {
                    HStack {
                        Text("Forza riduzione:").frame(width: 120)
                        Slider(value: Bindable(pipeline).noiseStrength, in: 0.1...1.0, step: 0.1)
                        Text("\(pipeline.noiseStrength, specifier: "%.1f")").frame(width: 60)
                    }
                }
            }
        }
    }

    // MARK: - Video

    private var videoSection: some View {
        GroupBox("Video") {
            VStack(spacing: 8) {
                Toggle("Portrait Box (9:16)", isOn: Bindable(pipeline).enablePortraitBox)
                if pipeline.enablePortraitBox {
                    HStack {
                        Text("Ritaglio:").frame(width: 80)
                        Picker("", selection: Bindable(pipeline).portraitCropMode) {
                            ForEach(["Center", "Top", "Bottom", "Smart"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                        Toggle("Sfondo sfocato", isOn: Bindable(pipeline).portraitBlurBackground)
                    }
                }

                Toggle("Overlay (PIP)", isOn: Bindable(pipeline).enableOverlay)
                if pipeline.enableOverlay {
                    HStack {
                        Button("Scegli video overlay") { pipeline.addOverlayVideo() }
                        if let ov = pipeline.overlayVideoURL { Text(ov.lastPathComponent).font(.caption) }
                    }
                    HStack {
                        Text("Posizione:").frame(width: 80)
                        Picker("", selection: Bindable(pipeline).overlayPosition) {
                            ForEach(["Top Left", "Top Right", "Bottom Left", "Bottom Right"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                        Text("Scala:").frame(width: 40)
                        Slider(value: Bindable(pipeline).overlayScale, in: 0.1...0.5).frame(width: 80)
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        GroupBox {
            DisclosureGroup("Opzioni avanzate", isExpanded: $showAdvanced) {
                VStack(spacing: 8) {
                    // Music + Ducking
                    Toggle("Musica + Auto-Ducking", isOn: Bindable(pipeline).enableMusicDucking)
                    if pipeline.enableMusicDucking {
                        HStack {
                            Button("Scegli musica") { pipeline.addMusicFile() }
                            if let m = pipeline.musicURL { Text(m.lastPathComponent).font(.caption) }
                        }
                        HStack {
                            Text("Volume musica:").frame(width: 110)
                            Slider(value: Bindable(pipeline).musicVolume, in: 0.0...1.0, step: 0.05)
                            Text("\(pipeline.musicVolume, specifier: "%.2f")").frame(width: 40)
                        }
                        HStack {
                            Text("Duck livello:").frame(width: 110)
                            Slider(value: Bindable(pipeline).duckLevel, in: 0.0...1.0, step: 0.05)
                            Text("\(pipeline.duckLevel, specifier: "%.2f")").frame(width: 40)
                        }
                    }

                    // Dual Language
                    Toggle("Sottotitoli bilingue", isOn: Bindable(pipeline).enableDualLanguage)
                    if pipeline.enableDualLanguage {
                        HStack {
                            Text("Seconda lingua:").frame(width: 120)
                            Picker("", selection: Bindable(pipeline).secondaryLanguage) {
                                ForEach(["en", "fr", "de", "es", "pt"], id: \.self) { Text($0.uppercased()).tag($0) }
                            }.labelsHidden()
                            Text("Modello trad.:").frame(width: 90)
                            Picker("", selection: Bindable(pipeline).translationModel) {
                                Text("(stesso)").tag("")
                                ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden()
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            if !pipeline.statusText.isEmpty {
                Text(pipeline.statusText).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressView(value: pipeline.progress, total: 1.0).progressViewStyle(.linear).tint(.accentColor)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        GroupBox("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(pipeline.log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("log-bottom")
                }
                .background(Color(white: 0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: pipeline.log) { _, _ in
                    withAnimation { proxy.scrollTo("log-bottom", anchor: .bottom) }
                }
            }
            .frame(minHeight: 100)
        }
    }
}

#Preview {
    ContentView()
        .environment(PipelineService())
        .frame(width: 750, height: 800)
}