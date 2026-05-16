import SwiftUI
import VideoEditCore

struct SettingsView: View {
    @Environment(PipelineService.self) private var pipeline
    @State private var apiKey: String = ""

    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gear") {
                generalPane
            }
            Tab("API", systemImage: "link") {
                apiPane
            }
        }
        .scenePadding()
        .frame(width: 500, height: 420)
        .task { apiKey = EnvLoader.load()["API_KEY"] ?? "" }
    }

    private var generalPane: some View {
        Form {
            Section("Modelli") {
                Picker("Modello Whisper predefinito", selection: Bindable(pipeline).asrModel) {
                    ForEach(PipelineService.availableModels, id: \.self) { Text($0).tag($0) }
                }

                Picker("Lingua predefinita", selection: Bindable(pipeline).language) {
                    ForEach(["it", "en", "fr", "de", "es", "pt", "ja", "zh", "auto"], id: \.self) { Text($0.uppercased()).tag($0) }
                }

                Picker("Profilo predefinito", selection: Bindable(pipeline).profileName) {
                    Text("Auto").tag("auto")
                    Text("Conversational").tag(ProfileName.conversational.rawValue)
                    Text("Lecturing").tag(ProfileName.lecturing.rawValue)
                    Text("Technical").tag(ProfileName.technical.rawValue)
                }
            }

            Section("Correzione") {
                Picker("Modello correzione", selection: Bindable(pipeline).textModel) {
                    Text("Nessuna").tag("")
                    ForEach(pipeline.availableTextModels, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var apiPane: some View {
        Form {
            Section("Endpoint") {
                HStack {
                    Text("URL API")
                    TextField("http://127.0.0.1:8000", text: Bindable(pipeline).apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Autenticazione") {
                HStack {
                    Text("API Key")
                    SecureField("Inserisci API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Necessaria solo se il server richiede autenticazione.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                HStack {
                    Spacer()
                    Button {
                        EnvLoader.save("API_KEY", value: apiKey)
                        Task { await pipeline.refreshAPIModels() }
                    } label: {
                        Label("Salva e verifica connessione", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}
