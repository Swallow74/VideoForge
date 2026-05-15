import os
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from pathlib import Path

from core.audio import extract_audio, is_audio_file
from core.transcribe import transcribe_file, ASR_MODELS, list_models
from core.merge import merge_and_group
from core.grammar import correct_segments
from core.srt import export_srt
from core.profiles import detect_profile
from core.config import PROFILES

DEFAULT_ASR = "large-v3"
DEFAULT_TEXT_MODEL = ""


class Video2SRTApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Video \u2192 SRT Transcriber")
        self.root.geometry("800x720")
        self.root.minsize(650, 550)

        self.files: list[str] = []
        self.lang_var = tk.StringVar(value="it")
        self.grammar_var = tk.BooleanVar(value=True)
        self.asr_model_var = tk.StringVar(value=DEFAULT_ASR)
        self.text_model_var = tk.StringVar(value=DEFAULT_TEXT_MODEL)
        self.profile_var = tk.StringVar(value="auto")

        self._build_ui()
        self._check_omlx()

    def _build_ui(self):
        main = ttk.Frame(self.root, padding=12)
        main.pack(fill=tk.BOTH, expand=True)

        header = ttk.Label(main, text="Video \u2192 SRT Transcriber",
                           font=("", 16, "bold"))
        header.pack(pady=(0, 8))

        file_frame = ttk.LabelFrame(main, text="File", padding=8)
        file_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        btn_frame = ttk.Frame(file_frame)
        btn_frame.pack(fill=tk.X, pady=(0, 4))
        ttk.Button(btn_frame, text="+ Aggiungi file",
                   command=self._add_files).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(btn_frame, text="\u2715 Rimuovi selezionati",
                   command=self._remove_selected).pack(side=tk.LEFT)

        self.file_listbox = tk.Listbox(file_frame, selectmode=tk.EXTENDED)
        self.file_listbox.pack(fill=tk.BOTH, expand=True)

        opts_frame = ttk.LabelFrame(main, text="Modelli e opzioni", padding=8)
        opts_frame.pack(fill=tk.X, pady=(0, 8))

        g1 = ttk.Frame(opts_frame)
        g1.pack(fill=tk.X, pady=2)
        ttk.Label(g1, text="Modello Whisper:", width=20).pack(side=tk.LEFT)
        self.asr_combo = ttk.Combobox(g1, textvariable=self.asr_model_var,
                                       values=ASR_MODELS, width=20, state="readonly")
        self.asr_combo.pack(side=tk.LEFT)

        g2 = ttk.Frame(opts_frame)
        g2.pack(fill=tk.X, pady=2)
        ttk.Label(g2, text="Modello correzione (omlx):", width=20).pack(side=tk.LEFT)
        self.text_combo = ttk.Combobox(g2, textvariable=self.text_model_var, width=40)
        self.text_combo.pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(g2, text="\u21bb", width=3,
                   command=self._refresh_models).pack(side=tk.RIGHT, padx=(4, 0))

        g3 = ttk.Frame(opts_frame)
        g3.pack(fill=tk.X, pady=2)
        ttk.Label(g3, text="Lingua:").pack(side=tk.LEFT, padx=(0, 4))
        ttk.Combobox(g3, textvariable=self.lang_var,
                     values=["it", "en", "fr", "de", "es", "pt", "ru", "ja", "zh", "auto"],
                     width=6, state="readonly").pack(side=tk.LEFT, padx=(0, 16))
        ttk.Checkbutton(g3, text="Correzione grammaticale AI",
                        variable=self.grammar_var).pack(side=tk.LEFT, padx=(0, 12))
        ttk.Label(g3, text="Profilo:").pack(side=tk.LEFT, padx=(0, 4))
        profile_combo = ttk.Combobox(g3, textvariable=self.profile_var,
                                      values=["auto", "conversational", "lecturing", "technical"],
                                      width=14, state="readonly")
        profile_combo.pack(side=tk.LEFT)

        progress_frame = ttk.Frame(main)
        progress_frame.pack(fill=tk.X, pady=(0, 4))

        self.progress_text = ttk.Label(progress_frame, text="",
                                       font=("Menlo", 9))
        self.progress_text.pack(anchor=tk.W)

        self.progress = ttk.Progressbar(progress_frame, mode="determinate")
        self.progress.pack(fill=tk.X)

        self.process_btn = ttk.Button(main, text="\u25b6 Avvia trascrizione",
                                      command=self._start_processing)
        self.process_btn.pack(pady=(0, 8))

        log_frame = ttk.LabelFrame(main, text="Log", padding=4)
        log_frame.pack(fill=tk.BOTH, expand=True)
        self.log_text = tk.Text(log_frame, height=8, wrap=tk.WORD,
                                state=tk.DISABLED, bg="#1e1e1e", fg="#d4d4d4",
                                font=("Menlo", 10))
        self.log_text.pack(fill=tk.BOTH, expand=True)

    def _refresh_models(self):
        models = list_models()
        if models:
            self.text_combo["values"] = models
            self._log(f"\u2713 Modelli omlx ({len(models)}): {', '.join(models)}")

    def _add_files(self):
        paths = filedialog.askopenfilenames(
            title="Seleziona file video/audio",
            filetypes=[
                ("Video/Audio", "*.mp4 *.mov *.mkv *.avi *.mp3 *.wav *.m4a *.aac *.ogg *.flac"),
                ("Tutti i file", "*.*"),
            ])
        for p in paths:
            if p and p not in self.files:
                self.files.append(p)
                self.file_listbox.insert(tk.END, Path(p).name)

    def _remove_selected(self):
        for i in reversed(self.file_listbox.curselection()):
            self.files.pop(i)
            self.file_listbox.delete(i)

    def _log(self, msg: str):
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, msg + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)
        self.root.update_idletasks()

    def _set_progress(self, pct: float, text: str = ""):
        self.progress["value"] = pct
        self.progress_text.config(text=text)
        self.root.update_idletasks()

    def _start_processing(self):
        if not self.files:
            messagebox.showwarning("Nessun file", "Aggiungi almeno un file.")
            return

        self.process_btn.config(state=tk.DISABLED)
        self._set_progress(0, "")
        threading.Thread(target=self._process_all, daemon=True).start()

    def _process_all(self):
        try:
            for f in self.files:
                self._process_single(f)
            self.root.after(0, lambda: messagebox.showinfo(
                "Completato", "Tutti i file sono stati processati!"))
        except Exception as e:
            err_msg = str(e)
            self.root.after(0, lambda m=err_msg: messagebox.showerror("Errore", m))
        finally:
            self.root.after(0, self._finish_processing)

    def _process_single(self, filepath: str):
        asr = self.asr_model_var.get().strip() or DEFAULT_ASR
        text_model = self.text_model_var.get().strip() or DEFAULT_TEXT_MODEL
        profile_name = self.profile_var.get()

        def log(msg):
            self.root.after(0, lambda: self._log(msg))

        def set_prog(pct, txt=""):
            self.root.after(0, lambda: self._set_progress(pct, txt))

        log(f"\n{'='*50}")
        log(f"File: {Path(filepath).name}")
        log(f"Whisper: {asr}  |  Correzione: {text_model}  |  Profilo: {profile_name}")

        audio_path = filepath
        if not is_audio_file(filepath):
            cache_path = filepath.rsplit(".", 1)[0] + "_audio.wav"
            if Path(cache_path).exists():
                log(f"Cache audio trovata: {Path(cache_path).name}")
            else:
                log("Estrazione audio...")
                set_prog(0, "Estrazione audio...")
            audio_path = extract_audio(filepath)
            log(f"Audio: {audio_path}")

        log("Caricamento modello Whisper...")
        set_prog(0, "Caricamento modello Whisper...")

        def on_raw_segment(seg):
            log(f"  [{_fmt(seg['start'])} \u2192 {_fmt(seg['end'])}] {seg['text']}")

        def on_progress(pct, current, total, *, elapsed=0, filtered=0):
            cur = _fmt(current)
            tot = _fmt(total)
            extra = f" | filt: {filtered}" if filtered else ""
            set_prog(pct, f"Trascrizione: {pct:.0f}%  ({cur} / {tot}){extra}")

        segments = transcribe_file(
            audio_path,
            language=self.lang_var.get() or None,
            model_size=asr,
            on_raw_segment=on_raw_segment,
            on_progress=on_progress,
        )
        log(f"Segmenti dopo filtro VAD: {len(segments)}")

        if not is_audio_file(filepath) and audio_path != filepath:
            os.remove(audio_path)

        if profile_name == "auto":
            profile = detect_profile(segments)
            log(f"Profilo rilevato: {profile['name']}")
        else:
            from core.config import PROFILES
            profile = PROFILES.get(profile_name, PROFILES["conversational"])
            log(f"Profilo manuale: {profile['name']}")

        log("Merge segmenti...")
        set_prog(0, "Merge segmenti...")
        segments = merge_and_group(segments, profile)
        log(f"Segmenti dopo merge: {len(segments)}")

        model_grammar = text_model if self.grammar_var.get() else ""

        def on_corrected(seg):
            log(f"  \u2713 [{_fmt(seg['start'])}] {seg['text']}")

        segments = correct_segments(
            segments,
            model=model_grammar,
            profile=profile,
            on_corrected=on_corrected if self.grammar_var.get() else None,
        )
        log(f"Segmenti finali: {len(segments)}")

        out = os.path.join(os.path.dirname(filepath), f"{Path(filepath).stem}.srt")
        export_srt(segments, out)
        log(f"SRT salvato: {out}")
        set_prog(100, "Completato!")

    def _finish_processing(self):
        self.progress["value"] = 100
        self.process_btn.config(state=tk.NORMAL)

    def _check_omlx(self):
        models = list_models()
        if models:
            self.text_combo["values"] = models
            self._log(f"\u2713 omlx su http://127.0.0.1:8000/v1 \u2014 modelli: {', '.join(models)}")
        else:
            self._log("\u26a0 omlx non rilevato. La correzione grammaticale non sara disponibile.")
            self._log("  La trascrizione locale funziona comunque.")


def _fmt(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def main():
    root = tk.Tk()
    Video2SRTApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
