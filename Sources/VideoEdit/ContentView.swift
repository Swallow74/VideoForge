import SwiftUI
import UniformTypeIdentifiers
import VideoEditCore

struct ContentView: View {
    @Environment(PipelineService.self) private var pipeline
    @State private var showTeleprompter = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            headerView.padding(.horizontal).padding(.top, 16)
            Divider().padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 12) {
                    filesSection
                    transcriptionSection
                    audioCleanupSection
                    videoSection
                    advancedSection
                    progressSection
                }
                .padding(.horizontal)
            }

            Divider().padding(.vertical, 8)
            logSection.padding(.horizontal)
        }
        .padding(.bottom, 16)
        .sheet(isPresented: $showTeleprompter) {
            TeleprompterView(service: pipeline.teleprompterService)
                .frame(minWidth: 600, minHeight: 500)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("VideoForge").font(.largeTitle.bold())
                .foregroundStyle(.primary)
            Spacer()
            if pipeline.isProcessing {
                ProgressView().scaleEffect(1.0).padding(.trailing, 6)
                    .controlSize(.large)
            }
            Button("📜 Teleprompter") { showTeleprompter = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Button(pipeline.isProcessing ? "Stop" : "▶  Avvia") {
                pipeline.isProcessing ? pipeline.cancel() : pipeline.start()
            }
            .disabled(pipeline.files.isEmpty && !pipeline.isProcessing)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        GroupBox("File") {
            VStack(spacing: 8) {
                HStack {
                    Button("＋ Aggiungi file") { pipeline.addFiles() }
                        .disabled(pipeline.isProcessing)
                        .controlSize(.large)
                    Button("✕ Rimuovi tutti") { pipeline.files.removeAll() }
                        .disabled(pipeline.files.isEmpty)
                        .controlSize(.large)
                    Spacer()
                    Text("\(pipeline.files.count) file").foregroundStyle(.secondary).font(.subheadline)
                }
                List(Array(pipeline.files.enumerated()), id: \.offset) { i, file in
                    HStack {
                        Image(systemName: AudioService.isAudioFile(file) ? "waveform" : "film")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                        Text(file.lastPathComponent)
                            .lineLimit(1)
                            .font(.body)
                        Spacer()
                    }
                    .swipeActions { Button("Rimuovi", role: .destructive) { pipeline.files.remove(at: i) } }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 100)
            }
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        GroupBox("Trascrizione") {
            VStack(spacing: 12) {
                HStack {
                    Text("Modello:").frame(width: 130, alignment: .leading).font(.body)
                    Picker("", selection: Bindable(pipeline).asrModel) {
                        ForEach(PipelineService.availableModels, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 180)
                        .controlSize(.large)
                    Text("Lingua:").frame(width: 60).font(.body)
                    Picker("", selection: Bindable(pipeline).language) {
                        ForEach(["it", "en", "fr", "de", "es", "pt", "ja", "zh", "auto"], id: \.self) { Text($0.uppercased()).tag($0) }
                    }.labelsHidden().frame(width: 90)
                        .controlSize(.large)
                }
                HStack {
                    Text("Correzione:").frame(width: 130, alignment: .leading).font(.body)
                    Picker("", selection: Bindable(pipeline).textModel) {
                        Text("(nessuno)").tag("")
                        ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 240)
                        .controlSize(.large)
                    Text("Profilo:").frame(width: 60).font(.body)
                    Picker("", selection: Bindable(pipeline).profileName) {
                        Text("Auto").tag("auto")
                        Text("Conversational").tag(ProfileName.conversational.rawValue)
                        Text("Lecturing").tag(ProfileName.lecturing.rawValue)
                        Text("Technical").tag(ProfileName.technical.rawValue)
                    }.labelsHidden().frame(width: 160)
                        .controlSize(.large)
                }
                HStack {
                    Text("API URL:").frame(width: 130, alignment: .leading).font(.body)
                    TextField("http://127.0.0.1:8000", text: Bindable(pipeline).apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .frame(width: 360)
                    Button("↻") {
                        Task { await pipeline.refreshAPIModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Rileva modelli disponibili dall'API")
                }
            }
        }
    }

    // MARK: - Audio Cleanup

    private var audioCleanupSection: some View {
        GroupBox("Pulizia Audio") {
            VStack(spacing: 12) {
                Toggle(isOn: Bindable(pipeline).enableSilenceRemoval) {
                    Text("Rimuovi silenzi").font(.body)
                }
                if pipeline.enableSilenceRemoval {
                    HStack {
                        Text("Soglia silenzio:").frame(width: 140, alignment: .leading).font(.body)
                        Slider(value: Bindable(pipeline).silenceThreshold, in: -50...(-10), step: 5)
                        Text("\(Int(pipeline.silenceThreshold)) dB").frame(width: 60).font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Durata min:").frame(width: 140, alignment: .leading).font(.body)
                        Slider(value: Bindable(pipeline).minSilenceDuration, in: 0.1...2.0, step: 0.1)
                        Text("\(pipeline.minSilenceDuration, specifier: "%.1f") s").frame(width: 60).font(.body.monospacedDigit())
                    }
                }

                Toggle(isOn: Bindable(pipeline).enableNoiseRemoval) {
                    Text("Rimuovi rumore fondo").font(.body)
                }
                if pipeline.enableNoiseRemoval {
                    HStack {
                        Text("Forza riduzione:").frame(width: 140, alignment: .leading).font(.body)
                        Slider(value: Bindable(pipeline).noiseStrength, in: 0.1...1.0, step: 0.1)
                        Text("\(pipeline.noiseStrength, specifier: "%.1f")").frame(width: 60).font(.body.monospacedDigit())
                    }
                }
            }
        }
    }

    // MARK: - Video

    private var videoSection: some View {
        GroupBox("Video") {
            VStack(spacing: 12) {
                Toggle(isOn: Bindable(pipeline).enablePortraitBox) {
                    Text("Portrait Box (9:16)").font(.body)
                }
                if pipeline.enablePortraitBox {
                    HStack {
                        Text("Ritaglio:").frame(width: 100, alignment: .leading).font(.body)
                        Picker("", selection: Bindable(pipeline).portraitCropMode) {
                            ForEach(["Center", "Top", "Bottom", "Smart"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().controlSize(.large)
                        Toggle("Sfondo sfocato", isOn: Bindable(pipeline).portraitBlurBackground)
                            .font(.body)
                    }
                }

                Toggle(isOn: Bindable(pipeline).enableOverlay) {
                    Text("Overlay (PIP)").font(.body)
                }
                if pipeline.enableOverlay {
                    HStack {
                        Button("Scegli video overlay") { pipeline.addOverlayVideo() }
                            .controlSize(.large)
                        if let ov = pipeline.overlayVideoURL {
                            Text(ov.lastPathComponent).font(.subheadline)
                        }
                    }
                    HStack {
                        Text("Posizione:").frame(width: 100, alignment: .leading).font(.body)
                        Picker("", selection: Bindable(pipeline).overlayPosition) {
                            ForEach(["Top Left", "Top Right", "Bottom Left", "Bottom Right"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().controlSize(.large)
                        Text("Scala:").frame(width: 50).font(.body)
                        Slider(value: Bindable(pipeline).overlayScale, in: 0.1...0.5)
                        Text("\(pipeline.overlayScale, specifier: "%.2f")").font(.body.monospacedDigit())
                            .frame(width: 50)
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        GroupBox {
            DisclosureGroup("Opzioni avanzate", isExpanded: $showAdvanced) {
                VStack(spacing: 12) {
                    Toggle(isOn: Bindable(pipeline).enableMusicDucking) {
                        Text("🎵 Musica + Auto-Ducking").font(.body)
                    }
                    if pipeline.enableMusicDucking {
                        HStack {
                            Button("Scegli musica") { pipeline.addMusicFile() }
                                .controlSize(.large)
                            if let m = pipeline.musicURL {
                                Text(m.lastPathComponent).font(.subheadline)
                            }
                        }
                        HStack {
                            Text("Volume musica:").frame(width: 140, alignment: .leading).font(.body)
                            Slider(value: Bindable(pipeline).musicVolume, in: 0.0...1.0, step: 0.05)
                            Text("\(pipeline.musicVolume, specifier: "%.2f")").font(.body.monospacedDigit())
                                .frame(width: 50)
                        }
                        HStack {
                            Text("Duck livello:").frame(width: 140, alignment: .leading).font(.body)
                            Slider(value: Bindable(pipeline).duckLevel, in: 0.0...1.0, step: 0.05)
                            Text("\(pipeline.duckLevel, specifier: "%.2f")").font(.body.monospacedDigit())
                                .frame(width: 50)
                        }
                    }

                    Toggle(isOn: Bindable(pipeline).enableDualLanguage) {
                        Text("🌐 Sottotitoli bilingue").font(.body)
                    }
                    if pipeline.enableDualLanguage {
                        HStack {
                            Text("Seconda lingua:").frame(width: 140, alignment: .leading).font(.body)
                            Picker("", selection: Bindable(pipeline).secondaryLanguage) {
                                ForEach(["en", "fr", "de", "es", "pt"], id: \.self) { Text($0.uppercased()).tag($0) }
                            }.labelsHidden().controlSize(.large)
                            Text("Modello trad.:").frame(width: 110).font(.body)
                            Picker("", selection: Bindable(pipeline).translationModel) {
                                Text("(stesso)").tag("")
                                ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().controlSize(.large)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            if !pipeline.statusText.isEmpty {
                Text(pipeline.statusText).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressView(value: pipeline.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .scaleEffect(y: 1.5)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        GroupBox("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(pipeline.log)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("log-bottom")
                }
                .background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: pipeline.log) { _, _ in
                    withAnimation { proxy.scrollTo("log-bottom", anchor: .bottom) }
                }
            }
            .frame(minHeight: 140)
        }
    }
}

#Preview {
    ContentView()
        .environment(PipelineService())
        .frame(width: 750, height: 800)
}