import { useState, useCallback, useRef, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { listen } from '@tauri-apps/api/event';
import { open } from '@tauri-apps/plugin-dialog';
import './App.css';

interface Segment {
  id: number; start: number; end: number; text: string; words: { word: string; start: number; end: number }[];
}

const MODELS = ['large-v3', 'large-v2', 'medium', 'small', 'base', 'tiny', 'qwen3-1.7b', 'qwen3-0.6b'];
const ENGINE_LABELS: Record<string, string> = {
  'large-v3': 'Whisper', 'large-v2': 'Whisper', 'medium': 'Whisper',
  'small': 'Whisper', 'base': 'Whisper', 'tiny': 'Whisper',
  'qwen3-1.7b': 'Qwen3-ASR', 'qwen3-0.6b': 'Qwen3-ASR',
};
const LANGUAGES = ['it', 'en', 'fr', 'de', 'es', 'pt', 'ja', 'zh', 'auto'];
const LANG_NAMES: Record<string, string> = { it: 'Italiano', en: 'English', fr: 'Français', de: 'Deutsch', es: 'Español', pt: 'Português', ja: '日本語', zh: '中文', auto: 'Auto' };

function App() {
  const [files, setFiles] = useState<string[]>([]);
  const [processing, setProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [statusText, setStatusText] = useState('');
  const [activeOp, setActiveOp] = useState('');
  const [log, setLog] = useState<string[]>([]);
  const [dropOver, setDropOver] = useState(false);
  const [_segments, _setSegments] = useState<Segment[] | null>(null);

  // Settings
  const [asrModel, setAsrModel] = useState('qwen3-1.7b');
  const [language, setLanguage] = useState('it');
  const [textModel, setTextModel] = useState('');
  const [profileName, setProfileName] = useState('auto');
  const [apiUrl, setApiUrl] = useState('http://127.0.0.1:8000');
  const [apiKey, setApiKey] = useState('');
  const [availableModels, setAvailableModels] = useState<string[]>([]);
  const [silence, setSilence] = useState(false);
  const [silenceThreshold, setSilenceThreshold] = useState(-30);
  const [silenceDuration, setSilenceDuration] = useState(0.75);
  const [noise, setNoise] = useState(false);
  const [noiseStrength, setNoiseStrength] = useState(0.5);
  const [portrait, setPortrait] = useState(false);
  const [portraitCrop, setPortraitCrop] = useState('Center');
  const [portraitBlur, setPortraitBlur] = useState(false);
  const [overlay, setOverlay] = useState(false);
  const [overlayPos, setOverlayPos] = useState('Bottom Right');
  const [overlayScale, setOverlayScale] = useState(0.25);
  const [music, setMusic] = useState(false);
  const [musicVolume, setMusicVolume] = useState(0.3);
  const [musicDuck, setMusicDuck] = useState(0.15);
  const [dualLang, setDualLang] = useState(false);
  const [secondaryLang, setSecondaryLang] = useState('en');

  const logRef = useRef<HTMLDivElement>(null);
  const logEndRef = useRef<HTMLDivElement>(null);

  const addLog = useCallback((msg: string) => {
    const ts = new Date().toLocaleTimeString();
    setLog(prev => [...prev, `[${ts}] ${msg}`]);
  }, []);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [log]);

  useEffect(() => {
    const listeners: Array<() => void> = [];

    (async () => {
      try {
        const u = await listen<string>('log-line', (e) => {
          addLog(e.payload);
        });
        listeners.push(u);
      } catch (_) { /* ignore */ }
    })();
    (async () => {
      try {
        const u = await listen<number>('ff-progress', (e) => {
          setProgress(e.payload);
        });
        listeners.push(u);
      } catch (_) { /* ignore */ }
    })();

    function extractPaths(payload: unknown): string[] {
      if (Array.isArray(payload) && payload.every(p => typeof p === 'string')) return payload;
      if (payload && typeof payload === 'object' && 'paths' in (payload as any) && Array.isArray((payload as any).paths))
        return (payload as any).paths.filter((p: any) => typeof p === 'string');
      return [];
    }

    (async () => {
      const win = getCurrentWindow();
      for (const [evt, handler] of [
        ['tauri://drag-enter', () => { setDropOver(true); }] as const,
        ['tauri://drag-over', () => setDropOver(true)] as const,
        ['tauri://drag-drop', async (paths: string[]) => {
          setDropOver(false);
          for (const p of paths) await invoke('add_file', { path: p });
          setFiles(await invoke<string[]>('get_files'));
        }] as const,
        ['tauri://drag-leave', () => setDropOver(false)] as const,
      ] as const) {
        try {
          const u = await win.listen(evt, (e: any) => {
            const paths = evt === 'tauri://drag-leave' ? [] : extractPaths(e.payload);
            (handler as any)(paths);
          });
          listeners.push(u);
        } catch (_) { /* ignore */ }
      }
    })();

    (async () => {
      try {
        const u = await listen<string[]>('f-drop-hover', () => {
          setDropOver(true);
        });
        listeners.push(u);
      } catch (_) { /* ignore */ }
      try {
        const u = await listen<string[]>('f-drop', async (e) => {
          setDropOver(false);
          for (const p of e.payload) await invoke('add_file', { path: p });
          setFiles(await invoke<string[]>('get_files'));
        });
        listeners.push(u);
      } catch (_) { /* ignore */ }
      try {
        const u = await listen<void>('f-drop-leave', () => {
          setDropOver(false);
        });
        listeners.push(u);
      } catch (_) { /* ignore */ }
    })();

    return () => { listeners.forEach(fn => fn()); };
  }, [addLog]);

  useEffect(() => {
    invoke<string[]>('get_files').then(setFiles).catch(() => {});
    invoke<Record<string, string>>('load_env').then(env => {
      if (env.API_KEY) setApiKey(env.API_KEY);
      if (env.API_BASE_URL) setApiUrl(env.API_BASE_URL);
    }).catch(() => {});
    if (apiUrl) {
      invoke<string[]>('list_models', { apiBaseUrl: apiUrl, apiKey }).then(setAvailableModels).catch(() => {});
    }
  }, []);

  const handleAddFiles = async () => {
    try {
      const selected = await open({
        multiple: true,
        filters: [{
          name: 'Video/Audio',
          extensions: ['mp4', 'mov', 'mkv', 'avi', 'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
        }],
      });
      if (!selected) return;
      const paths = Array.isArray(selected) ? selected : [selected];
      for (const p of paths) {
        await invoke('add_file', { path: p });
      }
      const updated = await invoke<string[]>('get_files');
      setFiles(updated);
      addLog(`Aggiunti ${paths.length} file`);
    } catch (e) { addLog(`Errore selezione file: ${e}`); }
  };

  const removeFile = async (i: number) => {
    await invoke('remove_file', { index: i });
    setFiles(await invoke<string[]>('get_files'));
  };

  const clearFiles = async () => {
    await invoke('clear_files');
    setFiles([]);
  };

  const runTranscription = async () => {
    if (files.length === 0) { addLog('✗ Nessun file selezionato'); return; }
    setProcessing(true); setProgress(0); setLog([]);

    addLog(`═══════════════════════════════════════════`);
    addLog(`File: ${files[0]}`);

    try {
      // 1. Extract audio
      setActiveOp('Estrazione audio');
      const audioPath = await invoke<string>('extract_audio', { videoPath: files[0] });
      addLog('✓ Audio estratto');

      // 2. Check venv
      const venvOk = await invoke<boolean>('check_venv');
      if (!venvOk) {
        addLog('Setup ambiente Python...');
        await invoke('setup_venv');
        addLog('✓ Ambiente Python pronto');
      }

      // 3. Transcribe
      setActiveOp(`Trascrizione (${asrModel})`);
      setProgress(0.3);
      const engine = asrModel.startsWith('qwen3-') ? asrModel : 'whisper';
      const engineLabel = ENGINE_LABELS[asrModel] || 'Whisper';
      addLog(`Trascrizione con ${engineLabel} ${asrModel}...`);
      const segs = await invoke<Segment[]>('transcribe', {
        audioPath, engine, model: asrModel, language: language === 'auto' ? null : language
      });
      _setSegments(segs);
      addLog(`✓ ${segs.length} segmenti`);

      // 4. Process pipeline
      setActiveOp('Elaborazione...');
      setProgress(0.7);
      const result = await invoke<Segment[]>('process_pipeline', {
        segments: segs, textModel: textModel || '', apiBaseUrl: apiUrl, apiKey
      });
      addLog(`✓ Merge: ${segs.length} → ${result.length} segmenti`);

      // 5. Export SRT
      setActiveOp('Export SRT');
      setProgress(0.9);
      const outPath = files[0].replace(/\.(mp4|mov|mkv|mp3|wav|m4a)$/, '.srt');
      await invoke('export_srt', { segments: result, outputPath: outPath });
      addLog(`✓ SRT: ${outPath}`);

      setProgress(1); setStatusText('Completato!');
      addLog('━ Elaborazione completata ━');
    } catch (e) {
      addLog(`✗ ERRORE: ${e}`);
    }
    setProcessing(false); setActiveOp('');
  };

  const outputPathFor = (inputPath: string, suffix: string): string => {
    const extRe = /\.(mp4|mov|mkv|avi|mp3|wav|m4a|ogg|flac)$/;
    return extRe.test(inputPath)
      ? inputPath.replace(extRe, `_${suffix}.$1`)
      : `${inputPath}_${suffix}`;
  };

  const handleCleanAudio = async () => {
    if (files.length === 0) { addLog('✗ Nessun file selezionato'); return; }
    setProcessing(true); setProgress(0); setLog([]);
    setStatusText('Pulizia audio in corso…');

    addLog(`═══════════════════════════════════════════`);
    addLog(`Pulisci Audio: ${files[0]}`);

    try {
      setActiveOp('Pulizia audio');
      addLog(`Rimozione silenzi: ${silence ? `soglia=${silenceThreshold}dB, durata=${silenceDuration}s` : 'no'}`);
      addLog(`Riduzione rumore: ${noise ? `forza=${noiseStrength}` : 'no'}`);

      const outPath = outputPathFor(files[0], 'clean');
      await invoke('clean_audio', {
        inputPath: files[0],
        outputPath: outPath,
        params: {
          remove_silence: silence,
          silence_threshold: silenceThreshold,
          silence_duration: silenceDuration,
          remove_noise: noise,
          noise_strength: noiseStrength,
        },
      });

      setStatusText('Completato!');
      addLog(`✓ Audio pulito: ${outPath}`);
      addLog('━ Pulizia audio completata ━');
    } catch (e) {
      addLog(`✗ ERRORE: ${e}`);
    }
    setProcessing(false);
    setActiveOp('');
  };

  const handleVideoProcessing = async () => {
    if (files.length === 0) { addLog('✗ Nessun file selezionato'); return; }
    setProcessing(true); setProgress(0); setLog([]);
    setStatusText('Elaborazione video in corso…');

    addLog(`═══════════════════════════════════════════`);
    addLog(`Elaborazione Video: ${files[0]}`);

    try {
      let overlayFilePath: string | null = null;
      if (overlay) {
        const sel = await open({
          multiple: false,
          filters: [{ name: 'Video', extensions: ['mp4', 'mov', 'mkv', 'avi'] }],
        });
        if (!sel) { addLog('✗ Nessun file overlay selezionato, annullato.'); setProcessing(false); return; }
        overlayFilePath = Array.isArray(sel) ? sel[0] : sel;
        addLog(`Overlay: ${overlayFilePath}`);
      }

      let musicFilePath: string | null = null;
      if (music) {
        const sel = await open({
          multiple: false,
          filters: [{ name: 'Audio', extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'] }],
        });
        if (!sel) { addLog('✗ Nessun file musica selezionato, annullato.'); setProcessing(false); return; }
        musicFilePath = Array.isArray(sel) ? sel[0] : sel;
        addLog(`Musica: ${musicFilePath}`);
      }

      setActiveOp('Elaborazione video');
      addLog(`Portrait: ${portrait ? `${portraitCrop}${portraitBlur ? ' + sfocato' : ''}` : 'no'}`);
      if (overlayFilePath) addLog(`PIP: ${overlayPos}, scala=${overlayScale}`);
      if (musicFilePath) addLog(`Musica: volume=${musicVolume}, duck=${musicDuck}`);

      const outPath = outputPathFor(files[0], 'processed');
      await invoke('process_video', {
        inputPath: files[0],
        outputPath: outPath,
        params: {
          portrait_crop: portrait,
          crop_position: portraitCrop,
          blur_bg: portraitBlur,
          overlay_path: overlayFilePath,
          overlay_position: overlayPos,
          overlay_scale: overlayScale,
          music_path: musicFilePath,
          music_volume: musicVolume,
          music_duck: musicDuck,
        },
      });

      setStatusText('Completato!');
      addLog(`✓ Video elaborato: ${outPath}`);
      addLog('━ Elaborazione video completata ━');
    } catch (e) {
      addLog(`✗ ERRORE: ${e}`);
    }
    setProcessing(false);
    setActiveOp('');
  };

  return (
    <div className="app">
      {/* Header */}
      <header className="header">
        <svg className="header-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <rect x="2" y="2" width="20" height="20" rx="2" /><path d="M7 8v8M12 6v12M17 10v4" />
        </svg>
        <h1>VideoForge</h1>
        <div className="header-actions">
          {processing && <button className="btn btn-danger" onClick={() => { addLog('⏹ Stop richiesto dall\'utente'); invoke('stop_processing'); }}>⏹ Stop</button>}
        </div>
      </header>

      {/* Content */}
      <div className="content">
        {/* Files */}
        <section className="card">
          <div className="card-header">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
            <h2>File</h2>
            <button className="btn" onClick={handleAddFiles} disabled={processing}>＋ Aggiungi</button>
            <button className="btn" onClick={clearFiles} disabled={files.length === 0 || processing}>✕ Rimuovi</button>
            <span style={{ fontSize: 13, color: 'var(--text-tertiary)' }}>{files.length} file</span>
          </div>
          {files.length === 0 ? (
            <div className={`dropzone ${dropOver ? 'dragover' : ''}`} onClick={handleAddFiles}>
              <div className="icon">📁</div>
              <p>{dropOver ? 'Rilascia per aggiungere' : 'Trascina file qui o clicca per selezionare'}</p>
            </div>
          ) : (
            <ul className="file-list">
              {files.map((f, i) => (
                <li key={i}>
                  <span style={{ opacity: 0.4 }}>{f.match(/\.(mp3|wav|m4a|aac)$/) ? '🎵' : '🎬'}</span>
                  {f}
                  <span className="remove" onClick={() => removeFile(i)}>✕</span>
                </li>
              ))}
            </ul>
          )}
        </section>

        {/* Launch Pad */}
        <section className="card">
          <div className="card-header"><h2>Launch Pad</h2></div>
          <div className="launch-grid">
            <button className="launch-tile launch-tile-primary" disabled={files.length === 0 || processing} onClick={runTranscription}>
              <svg className="launch-tile-icon" viewBox="0 0 24 24" fill="none" stroke="#3b82f6" strokeWidth="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
              <div><div className="launch-tile-text">Trascrizione</div><div className="launch-tile-sub">{textModel ? '+ Grammatica' : 'Solo SRT'}</div></div>
              <svg className="launch-tile-play" viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            </button>
            <button className="launch-tile" disabled={files.length === 0 || processing || (!silence && !noise)} onClick={handleCleanAudio}>
              <svg className="launch-tile-icon" viewBox="0 0 24 24" fill="none" stroke="#22c55e" strokeWidth="2"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/></svg>
              <div><div className="launch-tile-text">Pulisci Audio</div><div className="launch-tile-sub">Silenzi + Rumore</div></div>
              <svg className="launch-tile-play" viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            </button>
            <button className="launch-tile" disabled={files.length === 0 || processing || (!portrait && !overlay && !music)} onClick={handleVideoProcessing}>
              <svg className="launch-tile-icon" viewBox="0 0 24 24" fill="none" stroke="#8b5cf6" strokeWidth="2"><rect x="2" y="2" width="20" height="20" rx="2.18"/><line x1="2" y1="8" x2="22" y2="8"/></svg>
              <div><div className="launch-tile-text">Elabora Video</div><div className="launch-tile-sub">Ritaglia · PIP · Musica</div></div>
              <svg className="launch-tile-play" viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            </button>
          </div>
        </section>

        {/* Settings Grid */}
        <div className="settings-grid">
          {/* Transcription */}
          <section className="card">
            <div className="card-header">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
              <h2>Trascrizione</h2>
            </div>
            <div className="field"><label>Modello</label>
              <select value={asrModel} onChange={e => setAsrModel(e.target.value)}>
                {MODELS.map(m => <option key={m} value={m}>{m} ({ENGINE_LABELS[m] || 'Whisper'})</option>)}
              </select>
            </div>
            <div className="field"><label>Lingua</label>
              <select value={language} onChange={e => setLanguage(e.target.value)}>{LANGUAGES.map(l => <option key={l} value={l}>{l.toUpperCase()} — {LANG_NAMES[l]}</option>)}</select>
            </div>
            <div className="field"><label>Correzione</label>
              <select value={textModel} onChange={e => setTextModel(e.target.value)}>
                <option value="">Nessuna</option>
                {availableModels.map(m => <option key={m}>{m}</option>)}
              </select>
            </div>
            <div className="field"><label>Profilo</label>
              <select value={profileName} onChange={e => setProfileName(e.target.value)}>
                <option value="auto">Auto</option><option value="conversational">Conversational</option>
                <option value="lecturing">Lecturing</option><option value="technical">Technical</option>
              </select>
            </div>
            <div className="field"><label>API URL</label>
              <input value={apiUrl} onChange={e => setApiUrl(e.target.value)} onBlur={() => invoke('save_env', { key: 'API_BASE_URL', value: apiUrl })} placeholder="http://127.0.0.1:8000" />
            </div>
            <div className="field"><label>API Key</label>
              <input type="password" value={apiKey} onChange={e => setApiKey(e.target.value)} onBlur={() => invoke('save_env', { key: 'API_KEY', value: apiKey })} placeholder="Chiave API (opzionale)" />
            </div>
          </section>

          {/* Audio */}
          <section className="card">
            <div className="card-header">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
              <h2>Elaborazione Audio</h2>
            </div>
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={silence} onChange={e => setSilence(e.target.checked)}/><span className="slider"/></span>
              <label>Rimuovi silenzi</label>
            </label>
            {silence && <div className="indent">
              <div className="slider-row"><label>Soglia</label><input type="range" min={-50} max={-10} step={5} value={silenceThreshold} onChange={e => setSilenceThreshold(+e.target.value)}/><span className="val">{silenceThreshold} dB</span></div>
              <div className="slider-row"><label>Durata min</label><input type="range" min={0.1} max={2} step={0.1} value={silenceDuration} onChange={e => setSilenceDuration(+e.target.value)}/><span className="val">{silenceDuration.toFixed(1)} s</span></div>
            </div>}
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={noise} onChange={e => setNoise(e.target.checked)}/><span className="slider"/></span>
              <label>Rimuovi rumore</label>
            </label>
            {noise && <div className="indent">
              <div className="slider-row"><label>Forza</label><input type="range" min={0.1} max={1} step={0.1} value={noiseStrength} onChange={e => setNoiseStrength(+e.target.value)}/><span className="val">{noiseStrength.toFixed(1)}</span></div>
            </div>}
          </section>
        </div>

        {/* Video + Output */}
        <div className="settings-grid">
          {/* Video */}
          <section className="card">
            <div className="card-header">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="2" y="2" width="20" height="20" rx="2.18"/><line x1="2" y1="8" x2="22" y2="8"/></svg>
              <h2>Video</h2>
            </div>
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={portrait} onChange={e => setPortrait(e.target.checked)}/><span className="slider"/></span>
              <label>Portrait Box 9:16</label>
            </label>
            {portrait && <div className="indent" style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 8 }}>
              <select value={portraitCrop} onChange={e => setPortraitCrop(e.target.value)} style={{ flex: 1, padding: '4px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--text)' }}>
                <option>Center</option><option>Top</option><option>Bottom</option><option>Smart</option>
              </select>
              <label className="switch" style={{ width: 28, height: 16 }}><input type="checkbox" checked={portraitBlur} onChange={e => setPortraitBlur(e.target.checked)}/><span className="slider"/></label>
              <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Sfocato</span>
            </div>}
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={overlay} onChange={e => setOverlay(e.target.checked)}/><span className="slider"/></span>
              <label>Overlay PIP</label>
            </label>
            {overlay && <div className="indent">
              <div className="field"><label>Posizione</label>
                <select value={overlayPos} onChange={e => setOverlayPos(e.target.value)}>
                  <option>Top Left</option><option>Top Right</option><option>Bottom Left</option><option>Bottom Right</option>
                </select>
              </div>
              <div className="slider-row"><label>Scala</label><input type="range" min={0.1} max={0.5} step={0.05} value={overlayScale} onChange={e => setOverlayScale(+e.target.value)}/><span className="val">{overlayScale.toFixed(2)}</span></div>
            </div>}
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={music} onChange={e => setMusic(e.target.checked)}/><span className="slider"/></span>
              <label>Musica + Auto-Ducking</label>
            </label>
            {music && <div className="indent">
              <div className="slider-row"><label>Volume</label><input type="range" min={0} max={1} step={0.05} value={musicVolume} onChange={e => setMusicVolume(+e.target.value)}/><span className="val">{musicVolume.toFixed(2)}</span></div>
              <div className="slider-row"><label>Duck</label><input type="range" min={0} max={1} step={0.05} value={musicDuck} onChange={e => setMusicDuck(+e.target.value)}/><span className="val">{musicDuck.toFixed(2)}</span></div>
            </div>}
          </section>

          {/* Output */}
          <section className="card">
            <div className="card-header">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
              <h2>Output</h2>
            </div>
            <div className="toggle-row">
              <span className="switch"><input type="checkbox" checked disabled/><span className="slider" style={{ opacity: 0.5 }}/></span>
              <label>SRT <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>(sempre attivo)</span></label>
            </div>
            <label className="toggle-row">
              <span className="switch"><input type="checkbox" checked={dualLang} onChange={e => setDualLang(e.target.checked)}/><span className="slider"/></span>
              <label>Sottotitoli bilingue</label>
            </label>
            {dualLang && <div className="field indent"><label>Seconda lingua</label>
              <select value={secondaryLang} onChange={e => setSecondaryLang(e.target.value)}>
                {LANGUAGES.filter(l => l !== 'auto' && l !== language).map(l => <option key={l} value={l}>{l.toUpperCase()}</option>)}
              </select>
            </div>}
          </section>
        </div>

        {/* Progress — immediately above log, so scrolling reaches it quickly */}
        {statusText && <div className="progress">
          <div className="progress-header">
            <div className="info">
              <div className="title">{statusText}</div>
              {activeOp && <div className="sub">{activeOp}</div>}
            </div>
            <div className="pct">{Math.round(progress * 100)}%</div>
          </div>
          <div className="progress-bar"><div className="fill" style={{ width: `${progress * 100}%` }}/></div>
        </div>}

        {/* Log */}
        <section className="log">
          <div className="log-header">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="14" height="14"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
            <h3>Log</h3>
            {log.length > 0 && <button onClick={() => setLog([])}>Pulisci</button>}
          </div>
          <div className="log-body" ref={logRef}>
            {log.map((line, i) => <div key={i}>{line}</div>)}
            <div ref={logEndRef} />
          </div>
        </section>
      </div>
    </div>
  );
}

export default App;
