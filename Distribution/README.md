# VideoEdit Pro

**Trascrizione video → SRT, pulizia audio, portrait box, sottotitoli bilingue e molto altro.**
100% offline, nativo Apple Silicon, privacy garantita.

## Requisiti minimi

- macOS 15+ (Sequoia)
- Mac con chip Apple Silicon (M1/M2/M3/M4)
- ~8 GB di RAM consigliati
- 4 GB di spazio libero per i modelli AI

## Installazione rapida

### 1. Installa le dipendenze

Apri Terminale e incolla:

```bash
# Sposta l'app nelle Applicazioni
cp -R VideoEdit.app /Applications/

# Installa tutto con un comando
bash /Applications/VideoEdit.app/Contents/Resources/install.sh
```

Oppure apri l'app — il setup wizard integrato ti guiderà passo passo.

### 2. Avvia l'app

```bash
open /Applications/VideoEdit.app
```

## Sbloccare l'app (non certificata Apple)

Se macOS mostra _"VideoEdit non può essere aperto perché proviene da uno sviluppatore non identificato"_:

**Metodo 1 — Terminale (consigliato):**

```bash
xattr -dr com.apple.quarantine /Applications/VideoEdit.app
```

**Metodo 2 — Click destro:**

1. Tasto destro su `VideoEdit.app` → **Apri**
2. Nella finestra di dialogo clicca **Apri** (invece di spostare nel Cestino)

**Metodo 3 — Impostazioni di sistema:**

1. Vai in **Impostazioni di Sistema** → **Privacy e Sicurezza**
2. Scorri fino a _"VideoEdit è stato bloccato per proteggere il Mac"_
3. Clicca **"Apri comunque"**

Dopo uno di questi passaggi, l'app si apre normalmente.

## Come usarla

### 1. Trascrizione base

1. Aggiungi un file video (`+ Aggiungi file`)
2. Scegli la lingua (es. `IT`)
3. Clicca `▶ Avvia`
4. L'app genera il file `.srt` accanto al video originale

### 2. Correzione grammaticale (opzionale)

Prima avvia un motore LLM locale:

```bash
# Con omlx (consigliato)
omlx serve --model qwen3-vl-8b

# Con Ollama
ollama pull qwen3:8b
ollama serve
```

Poi nell'app:
1. Seleziona il modello nel menu a tendina "Correzione"
2. Se necessario, modifica l'**API URL** (default: `http://127.0.0.1:8000`)
3. Clicca `↻` per aggiornare la lista modelli

URL per motori comuni:

| Motore | URL |
|---|---|
| omlx | `http://127.0.0.1:8000` |
| Ollama | `http://127.0.0.1:11434` |
| LM Studio | `http://127.0.0.1:1234` |
| OpenAI API | `https://api.openai.com/v1` |

### 3. Pulizia audio

- **Rimuovi silenzi**: taglia automaticamente le pause lunghe
- **Rimuovi rumore**: filtro anlmdn per ridurre il rumore di fondo

### 4. Video

- **Portrait Box**: crop 9:16 per Shorts/Reels (con sfondo sfocato opzionale)
- **Overlay PIP**: sovrapponi un secondo video (webcam/screen)

### 5. Opzioni avanzate

- **Musica + Auto-Ducking**: aggiungi musica di sottofondo che si abbassa quando parli
- **Sottotitoli bilingue**: genera SRT in due lingue (es. IT + EN)

## Funzionalità complete

| Funzione | Descrizione |
|---|---|
| **Trascrizione AI** | Whisper large-v3 via MLX (nativo Apple Silicon) |
| **Correzione grammaticale** | Tramite LLM locale (omlx, Ollama, LM Studio) |
| **Boundary scoring adattivo** | Punteggiatura automatica basata su gap, casing, connettivi |
| **Rimozione silenzi** | Taglia pause > soglia configurabile |
| **Rimozione rumore** | Filtro anlmdn + highpass per preservare la voce |
| **Portrait Box** | Crop 9:16 con centro/alto/basso/sfocato |
| **Overlay PIP** | Picture-in-picture con posizione e scala regolabili |
| **Musica + ducking** | Sidechain compression: musica si abbassa quando parli |
| **SRT bilingue** | Doppia lingua nello stesso file (primario + traduzione) |
| **Batch processing** | Elabora più file in sequenza |
| **Profili dinamici** | Conversazionale / Lecturing / Technical — auto-rilevati |
| **Cache correzioni** | SHA256 — evita chiamate API ridondanti |
| **Teleprompter** | Script scorrevole con velocità regolabile |
| **API configurabile** | Supporta omlx, Ollama, LM Studio, OpenAI |

## Struttura del progetto

```
VideoEdit Pro.app/
├── Contents/
│   ├── MacOS/VideoEdit          # App nativa arm64
│   ├── Resources/
│   │   ├── transcribe_audio.py  # Bridge Python per trascrizione
│   │   └── install.sh           # Script installazione dipendenze
│   └── Info.plist
```

## Architettura

```
Video   →  ffmpeg (audio extraction)
         →  Whisper (MLX / Python)  →  trascrizione con timestamp
         →  Merge (boundary-aware)  →  segmenti raggruppati
         →  LLM (omlx/Ollama)       →  correzione grammaticale (opzionale)
         →  Boundary scoring        →  punteggiatura automatica
         →  SRT Exporter            →  file .srt
```

Il core logico (boundary scoring, merge, normalizzazione, profili, esportazione SRT) è implementato in **Swift puro** (`VideoEditCore`). La trascrizione usa **mlx-whisper** via Python bridge, con architettura MLX già pronta per migrazione nativa futura.

## Sviluppo

```bash
git clone <repo>
cd videoedit
swift build                     # Compila
swift test                      # 46 test
swift run VideoEdit             # Avvia
swift build -c release          # Build release
```

## Licenza

MIT
