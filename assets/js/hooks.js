import * as THREE from "three"

// ── Helpers ──────────────────────────────────────────────────────────────────

function dispatchTtsDone() {
  window.dispatchEvent(new CustomEvent("tts:done"))
}

// ── AudioPlayer ──────────────────────────────────────────────────────────────

export const AudioPlayer = {
  mounted() {
    this.audioCtx = null
    this.voice = null
    this.speakQueue = []
    this.isSpeaking = false
    this.textBuffer = ""
    this.lastReplayText = ""
    this.lastAudioBuffer = null
    this.playbackMode = "browser"
    this.chatVoiceId = null
    this.kokoroActive = false
    this.serverTtsActive = false
    this.ttsSeq = 0
    this.audioChunkQueue = {}
    this.nextPlaySeq = 1
    this.isPlayingChunk = false
    this.streamingDone = false
    this.finalChunkSeq = 0
    this.currentSource = null

    const pickVoice = () => {
      const voices = window.speechSynthesis.getVoices()
      const candidates = [
        voices.find(v => v.name === "Google US English"),
        voices.find(v => v.name.includes("Google") && v.lang === "en-US"),
        voices.find(v => v.name.includes("Google") && v.lang.startsWith("en")),
        voices.find(v => v.name.includes("Premium") && v.lang.startsWith("en")),
        voices.find(v => v.name.includes("Enhanced") && v.lang.startsWith("en")),
        voices.find(v => v.name === "Samantha"),
        voices.find(v => v.name === "Alex"),
        voices.find(v => v.lang === "en-US" && !v.name.toLowerCase().includes("compact")),
        voices.find(v => v.lang.startsWith("en")),
      ]
      this.voice = candidates.find(Boolean) || null
    }

    if (window.speechSynthesis.getVoices().length > 0) {
      pickVoice()
    } else {
      window.speechSynthesis.addEventListener("voiceschanged", pickVoice, { once: true })
    }

    const BTN = [
      "flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[11px] cursor-pointer select-none",
      "transition-all duration-150",
      "text-black/35 dark:text-white/35 bg-black/[0.04] dark:bg-white/[0.04]",
      "hover:text-black/60 dark:hover:text-white/60 hover:bg-black/[0.07] dark:hover:bg-white/[0.06]",
    ].join(" ")

    const BARS = `<span class="flex items-end gap-[2.5px] h-3 shrink-0">
      <span class="w-[2.5px] rounded-full bg-current animate-bounce" style="height:55%;animation-delay:0ms"></span>
      <span class="w-[2.5px] rounded-full bg-current animate-bounce" style="height:100%;animation-delay:100ms"></span>
      <span class="w-[2.5px] rounded-full bg-current animate-bounce" style="height:75%;animation-delay:50ms"></span>
      <span class="w-[2.5px] rounded-full bg-current animate-bounce" style="height:90%;animation-delay:150ms"></span>
      <span class="w-[2.5px] rounded-full bg-current animate-bounce" style="height:60%;animation-delay:25ms"></span>
    </span>`

    const ICON_PAUSE = `<svg class="w-3 h-3 shrink-0" fill="currentColor" viewBox="0 0 24 24">
      <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>
    </svg>`

    const ICON_PLAY = `<svg class="w-3 h-3 shrink-0" fill="currentColor" viewBox="0 0 24 24">
      <path d="M8 5v14l11-7z"/>
    </svg>`

    const ICON_REPLAY = `<svg class="w-3.5 h-3.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
      <path d="M3 3v5h5"/>
    </svg>`

    const updateBar = (state) => {
      const bar = document.getElementById("playback-bar")
      if (!bar) return
      if (state === "idle") { bar.innerHTML = ""; return }
      if (state === "playing") {
        bar.innerHTML = `<button id="tts-ctrl" class="${BTN}">${BARS}${ICON_PAUSE}<span>Pause</span></button>`
        document.getElementById("tts-ctrl")?.addEventListener("click", pausePlayback)
        return
      }
      if (state === "paused") {
        bar.innerHTML = `<button id="tts-ctrl" class="${BTN}">${ICON_PLAY}<span>Resume</span></button>`
        document.getElementById("tts-ctrl")?.addEventListener("click", resumePlayback)
        return
      }
      if (state === "replay") {
        bar.innerHTML = `<button id="tts-ctrl" class="${BTN}">${ICON_REPLAY}<span>Replay</span></button>`
        document.getElementById("tts-ctrl")?.addEventListener("click", replayPlayback)
        return
      }
    }

    const pausePlayback = () => {
      if (this.playbackMode === "kokoro" && this.audioCtx) {
        this.audioCtx.suspend()
      } else {
        window.speechSynthesis.pause()
      }
      updateBar("paused")
    }

    const resumePlayback = () => {
      if (this.playbackMode === "kokoro" && this.audioCtx) {
        this.audioCtx.resume()
      } else {
        window.speechSynthesis.resume()
      }
      updateBar("playing")
    }

    const replayPlayback = () => {
      if (this.playbackMode === "kokoro" && this.lastAudioBuffer) {
        if (!this.audioCtx) this.audioCtx = new AudioContext()
        const src = this.audioCtx.createBufferSource()
        src.buffer = this.lastAudioBuffer
        src.connect(this.audioCtx.destination)
        src.onended = () => { updateBar("replay"); dispatchTtsDone() }
        src.start()
        updateBar("playing")
        return
      }
      if (this.lastReplayText) {
        cancelAll()
        this.speakQueue = this.lastReplayText
          .replace(/```[\s\S]*?```/g, "")
          .replace(/`[^`]+`/g, "")
          .replace(/[#*_~>|]/g, "")
          .replace(/\n+/g, " ")
          .replace(/\s{2,}/g, " ")
          .trim()
          .split(/(?<=[.!?])\s+/)
          .map(s => s.trim())
          .filter(Boolean)
        speakNext()
        updateBar("playing")
      }
    }

    const CHAT_VOICE_CHARS = {
      af_heart:    { pitch: 1.05, rate: 1.05 },
      af_bella:    { pitch: 1.10, rate: 1.10 },
      af_nicole:   { pitch: 1.00, rate: 0.95 },
      af_sky:      { pitch: 1.12, rate: 1.12 },
      am_adam:     { pitch: 0.80, rate: 0.95 },
      am_michael:  { pitch: 0.90, rate: 1.05 },
      bf_emma:     { pitch: 1.05, rate: 0.95 },
      bf_isabella: { pitch: 1.00, rate: 0.90 },
      bm_george:   { pitch: 0.75, rate: 0.90 },
      bm_lewis:    { pitch: 0.85, rate: 0.95 },
    }

    const pickVoiceFor = (voiceId) => {
      const all = window.speechSynthesis.getVoices()
      if (!all.length) return null
      const isUK     = voiceId && voiceId.startsWith("b")
      const isFemale = voiceId && voiceId[1] === "f"
      const prefLang = isUK ? "en-GB" : "en-US"
      const FEMALE = /female|samantha|zira|kate|hazel|victoria|moira|fiona|karen|tessa/i
      const MALE   = /\bmale\b|alex|david|daniel|george|rishi|oliver|arthur/i
      let best = null, bestScore = -Infinity
      for (const v of all) {
        if (!v.lang.startsWith("en")) continue
        let s = 0
        if (v.lang === prefLang) s += 8
        else if (v.lang.startsWith("en")) s += 1
        if (isFemale  && FEMALE.test(v.name)) s += 6
        if (!isFemale && MALE.test(v.name))   s += 6
        if (/premium|enhanced/i.test(v.name)) s += 2
        if (/compact/i.test(v.name))          s -= 3
        if (s > bestScore) { bestScore = s; best = v }
      }
      return best
    }

    const speakNext = () => {
      if (this.speakQueue.length === 0) {
        this.isSpeaking = false
        if (this.lastReplayText) updateBar("replay")
        dispatchTtsDone()
        return
      }
      if (!this.isSpeaking) {
        this.playbackMode = "browser"
        updateBar("playing")
      }
      this.isSpeaking = true
      const text = this.speakQueue.shift()
      const utt = new SpeechSynthesisUtterance(text)
      const chars = CHAT_VOICE_CHARS[this.chatVoiceId] || { pitch: 1.0, rate: 1.1 }
      const matched = this.chatVoiceId ? pickVoiceFor(this.chatVoiceId) : null
      utt.voice = matched || this.voice
      utt.pitch = chars.pitch
      utt.rate  = chars.rate
      utt.onend = speakNext
      window.speechSynthesis.speak(utt)
    }

    const enqueue = (text) => {
      const clean = text
        .replace(/```[\s\S]*?```/g, "")
        .replace(/`[^`]+`/g, "")
        .replace(/[#*_~>|]/g, "")
        .replace(/\n+/g, " ")
        .replace(/\s{2,}/g, " ")
        .trim()
      if (!clean) return
      this.speakQueue.push(clean)
      if (!this.isSpeaking) speakNext()
    }

    const drainBuffer = (flush = false) => {
      this.textBuffer = this.textBuffer.replace(/\n{2,}/g, ". ")
      const re = /^(.{10,}?[.!?])\s+/
      let match
      while ((match = this.textBuffer.match(re))) {
        enqueue(match[1])
        this.textBuffer = this.textBuffer.slice(match[0].length)
      }
      if (flush && this.textBuffer.trim()) {
        enqueue(this.textBuffer.trim())
        this.textBuffer = ""
      }
    }

    const drainBufferForKokoro = () => {
      this.textBuffer = this.textBuffer.replace(/\n{2,}/g, ". ")
      const re = /^(.{40,}?[.!?])\s+/
      let match
      while ((match = this.textBuffer.match(re))) {
        const clean = match[1]
          .replace(/```[\s\S]*?```/g, "")
          .replace(/`[^`]+`/g, "")
          .replace(/[#*_~>|]/g, "")
          .replace(/\n+/g, " ")
          .replace(/\s{2,}/g, " ")
          .trim()
        if (clean) {
          this.ttsSeq++
          this.pushEvent("tts_request", { text: clean, seq: this.ttsSeq })
        }
        this.textBuffer = this.textBuffer.slice(match[0].length)
      }
    }

    const playNextChunk = () => {
      if (this.isPlayingChunk) return
      const data = this.audioChunkQueue[this.nextPlaySeq]
      if (!data) {
        if (this.streamingDone && this.nextPlaySeq > this.finalChunkSeq) {
          updateBar("replay")
          dispatchTtsDone()
        }
        return
      }
      delete this.audioChunkQueue[this.nextPlaySeq]
      this.nextPlaySeq++
      this.isPlayingChunk = true
      this.playbackMode = "kokoro"
      updateBar("playing")
      const binary = atob(data)
      const bytes = new Uint8Array(binary.length)
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
      if (!this.audioCtx) this.audioCtx = new AudioContext()
      this.audioCtx.decodeAudioData(bytes.buffer.slice(0), (buffer) => {
        this.lastAudioBuffer = buffer
        const source = this.audioCtx.createBufferSource()
        this.currentSource = source
        source.buffer = buffer
        source.connect(this.audioCtx.destination)
        source.onended = () => {
          this.currentSource = null
          this.isPlayingChunk = false
          if (this.audioChunkQueue[this.nextPlaySeq]) {
            playNextChunk()
          } else if (this.streamingDone && this.nextPlaySeq > this.finalChunkSeq) {
            updateBar("replay")
            dispatchTtsDone()
          }
        }
        source.start()
      })
    }

    const cancelAll = () => {
      window.speechSynthesis.cancel()
      this.speakQueue = []
      this.isSpeaking = false
      this.textBuffer = ""
      this.ttsSeq = 0
      this.audioChunkQueue = {}
      this.nextPlaySeq = 1
      this.isPlayingChunk = false
      this.streamingDone = false
      this.finalChunkSeq = 0
      if (this.currentSource) {
        try { this.currentSource.stop() } catch (_) {}
        this.currentSource = null
      }
    }

    this.handleEvent("stream_token", ({ token }) => {
      this.lastReplayText += token
      if (this.kokoroActive) {
        this.textBuffer += token
        drainBufferForKokoro()
      } else if (!this.serverTtsActive) {
        this.textBuffer += token
        drainBuffer()
      }
    })

    this.handleEvent("stream_done", ({ chatterbox, kokoro }) => {
      if (kokoro) {
        const remaining = (this.textBuffer || "")
          .replace(/```[\s\S]*?```/g, "")
          .replace(/`[^`]+`/g, "")
          .replace(/[#*_~>|]/g, "")
          .replace(/\n+/g, " ")
          .replace(/\s{2,}/g, " ")
          .trim()
        this.textBuffer = ""
        if (remaining) {
          this.ttsSeq++
          this.pushEvent("tts_request", { text: remaining, seq: this.ttsSeq })
        }
        this.streamingDone = true
        this.finalChunkSeq = this.ttsSeq
        if (this.ttsSeq === 0) dispatchTtsDone()
      } else if (chatterbox) {
        // Chatterbox/XTTS: play_audio event will fire, nothing to do here
      } else {
        drainBuffer(true)
      }
    })

    this.handleEvent("stream_cancel", ({ voice_id, kokoro_active, server_tts }) => {
      cancelAll()
      this.lastReplayText = ""
      this.lastAudioBuffer = null
      if (voice_id) this.chatVoiceId = voice_id
      this.kokoroActive = kokoro_active === true
      this.serverTtsActive = server_tts === true
      updateBar("idle")
    })

    this.handleEvent("set_chat_voice", ({ voice_id, kokoro_active, server_tts }) => {
      this.chatVoiceId = voice_id
      this.kokoroActive = kokoro_active === true
      this.serverTtsActive = server_tts === true
    })

    this.handleEvent("play_audio", ({ data }) => {
      cancelAll()
      this.playbackMode = "kokoro"
      const binary = atob(data)
      const bytes = new Uint8Array(binary.length)
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
      if (!this.audioCtx) this.audioCtx = new AudioContext()
      this.audioCtx.decodeAudioData(bytes.buffer.slice(0), (buffer) => {
        this.lastAudioBuffer = buffer
        const source = this.audioCtx.createBufferSource()
        this.currentSource = source
        source.buffer = buffer
        source.connect(this.audioCtx.destination)
        source.onended = () => { this.currentSource = null; updateBar("replay"); dispatchTtsDone() }
        source.start()
        updateBar("playing")
      })
    })

    this.handleEvent("play_audio_chunk", ({ seq, data }) => {
      this.audioChunkQueue[seq] = data
      playNextChunk()
    })

    this.handleEvent("live_done", ({ final_seq }) => {
      this.streamingDone = true
      this.finalChunkSeq = final_seq || 0
      // If all chunks already arrived and finished playing, fire tts:done now
      if (!this.isPlayingChunk && this.nextPlaySeq > this.finalChunkSeq) {
        updateBar("replay")
        dispatchTtsDone()
      } else {
        playNextChunk()
      }
    })

    this.handleEvent("skip_audio_chunk", ({ seq }) => {
      if (seq === this.nextPlaySeq) {
        this.nextPlaySeq++
        playNextChunk()
      }
    })

    document.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-tts-play]")
      if (!btn) return
      const text = btn.dataset.ttsContent
      if (!text) return
      cancelAll()
      this.lastReplayText = text
      this.lastAudioBuffer = null
      this.playbackMode = "browser"
      this.speakQueue = text
        .replace(/```[\s\S]*?```/g, "")
        .replace(/`[^`]+`/g, "")
        .replace(/[#*_~>|]/g, "")
        .replace(/\n+/g, " ")
        .replace(/\s{2,}/g, " ")
        .trim()
        .split(/(?<=[.!?])\s+/)
        .map(s => s.trim())
        .filter(Boolean)
      speakNext()
    })

    const PREVIEW_VOICE_CHARS = {
      af_heart:    { pitch: 0.75, rate: 0.99 },
      af_bella:    { pitch: 1.12, rate: 1.06 },
      af_nicole:   { pitch: 1.00, rate: 0.91 },
      af_sky:      { pitch: 1.18, rate: 1.12 },
      am_adam:     { pitch: 0.74, rate: 0.92 },
      am_michael:  { pitch: 0.88, rate: 1.01 },
      bf_emma:     { pitch: 1.06, rate: 0.92 },
      bf_isabella: { pitch: 0.97, rate: 0.87 },
      bm_george:   { pitch: 0.70, rate: 0.87 },
      bm_lewis:    { pitch: 0.82, rate: 0.93 },
    }

    this.handleEvent("speak_preview", ({ text, voice_id }) => {
      cancelAll()
      const clean = text.replace(/[#*_~>|]/g, "").replace(/\n+/g, " ").trim()
      if (!clean) return
      const chars = PREVIEW_VOICE_CHARS[voice_id] || { pitch: 1.0, rate: 1.0 }
      const utt = new SpeechSynthesisUtterance(clean)
      const matched = pickVoiceFor(voice_id)
      if (matched) utt.voice = matched
      utt.pitch = chars.pitch
      utt.rate  = chars.rate
      window.speechSynthesis.speak(utt)
    })

    this.handleEvent("open_url", ({ url }) => {
      window.open(url, "_blank", "noopener,noreferrer")
    })
  },
}

// ── MicRecorder ──────────────────────────────────────────────────────────────

export const MicRecorder = {
  mounted() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SR) {
      this.el.title = "Speech recognition not supported in this browser"
      this.el.style.opacity = "0.3"
      return
    }

    const recognition = new SR()
    recognition.continuous = false
    recognition.interimResults = false
    recognition.lang = "en-US"

    let active = false

    const start = () => { recognition.start(); active = true; this.pushEvent("set_recording", { value: true }) }
    const stop  = () => { recognition.stop();  active = false; this.pushEvent("set_recording", { value: false }) }

    recognition.onresult = (e) => {
      const text = e.results[0][0].transcript.trim()
      if (text) this.pushEvent("transcription_result", { text })
      active = false
      this.pushEvent("set_recording", { value: false })
    }

    recognition.onerror = () => { active = false; this.pushEvent("set_recording", { value: false }) }
    recognition.onend   = () => { active = false; this.pushEvent("set_recording", { value: false }) }

    this.el.addEventListener("click", () => { active ? stop() : start() })
  },
}

// ── ChatInput ─────────────────────────────────────────────────────────────────

export const ChatInput = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) e.preventDefault()
    })
  },
}

// ── VoiceOrb ──────────────────────────────────────────────────────────────────

// Simple pass-through — all magic is in the fragment shader.
const VERTEX_SHADER = `
  varying vec3 vNormal;
  varying vec3 vViewDir;

  void main() {
    vNormal  = normalize(normalMatrix * normal);
    vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
    vViewDir = normalize(-mvPos.xyz);
    gl_Position = projectionMatrix * mvPos;
  }
`

// Siri-style: drifting pastel blobs beneath a pearl surface + golden fresnel rim.
const FRAGMENT_SHADER = `
  uniform float uTime;
  uniform float uSpeed;
  uniform float uAudioLevel;
  uniform vec3  uBlobA;
  uniform vec3  uBlobB;
  uniform vec3  uBlobC;
  uniform vec3  uRimColor;

  varying vec3 vNormal;
  varying vec3 vViewDir;

  // Soft exponential blob weight based on angular distance
  float blob(vec3 n, vec3 center, float spread) {
    return exp(-distance(n, center) / spread);
  }

  void main() {
    float t = uTime * uSpeed;
    float a = uAudioLevel;

    // Four blob centers drifting around the sphere
    vec3 p1 = normalize(vec3(sin(t*0.61),        cos(t*0.47),        sin(t*0.33)));
    vec3 p2 = normalize(vec3(cos(t*0.37 + 1.57), sin(t*0.71 + 0.8),  cos(t*0.53)));
    vec3 p3 = normalize(vec3(sin(t*0.43 + 2.09), cos(t*0.29 + 1.30), sin(t*0.81)));
    vec3 p4 = normalize(vec3(cos(t*0.59 + 0.39), sin(t*0.38 + 2.20), cos(t*0.23 + 1.10)));

    float spread = 0.52 + a * 0.22;

    float w1 = blob(vNormal, p1, spread);
    float w2 = blob(vNormal, p2, spread * 0.88);
    float w3 = blob(vNormal, p3, spread * 0.96);
    float w4 = blob(vNormal, p4, spread * 0.78);
    float wSum = w1 + w2 + w3 + w4;

    // Weighted average of blob colours
    vec3 blobCol = (uBlobA*w1 + uBlobB*w2 + uBlobC*w3 + mix(uBlobA, uBlobC, 0.5)*w4)
                   / max(wSum, 0.001);

    // Pearl-white base
    vec3 base = vec3(0.99, 0.96, 0.97);

    // Blobs are strongest at the silhouette, faint at center
    float facing  = max(dot(vNormal, vViewDir), 0.0);
    float edgeness = 1.0 - facing;
    float blobMix = min(wSum * 0.32, 0.68) * (0.35 + edgeness * 0.65);
    vec3 color = mix(base, blobCol, blobMix);

    // Pearl centre — very bright / white
    float centerGlow = pow(facing, 1.6);
    color = mix(color, vec3(1.0, 0.985, 0.97), centerGlow * 0.88);

    // Golden fresnel rim
    float fresnel = pow(1.0 - facing, 2.8);
    color = mix(color, uRimColor, fresnel * 0.82);

    // Specular hotspot
    vec3  lightDir = normalize(vec3(0.35, 0.55, 1.0));
    float spec     = pow(max(dot(reflect(-lightDir, vNormal), vViewDir), 0.0), 28.0);
    color += spec * 0.14;

    gl_FragColor = vec4(color, 1.0);
  }
`

// Per-state target values
const ORB_STATES = {
  idle: {
    speed:    0.32,
    blobA:    new THREE.Color("#f9a8d4"), // pink-300
    blobB:    new THREE.Color("#c084fc"), // purple-400
    blobC:    new THREE.Color("#fbbf24"), // amber-400
    rimColor: new THREE.Color("#fde68a"), // amber-200
    label:    "Say something…",
  },
  listening: {
    speed:    0.60,
    blobA:    new THREE.Color("#f9a8d4"),
    blobB:    new THREE.Color("#fbbf24"),
    blobC:    new THREE.Color("#67e8f9"), // cyan-300
    rimColor: new THREE.Color("#fde68a"),
    label:    "Listening…",
  },
  thinking: {
    speed:    1.55,
    blobA:    new THREE.Color("#93c5fd"), // blue-300
    blobB:    new THREE.Color("#c084fc"),
    blobC:    new THREE.Color("#f9a8d4"),
    rimColor: new THREE.Color("#bfdbfe"), // blue-200
    label:    "Thinking…",
  },
  speaking: {
    speed:    0.90,
    blobA:    new THREE.Color("#fbbf24"),
    blobB:    new THREE.Color("#f9a8d4"),
    blobC:    new THREE.Color("#6ee7b7"), // emerald-300
    rimColor: new THREE.Color("#fde68a"),
    label:    "Speaking…",
  },
}

function lerpColor(a, b, t) {
  return new THREE.Color(
    a.r + (b.r - a.r) * t,
    a.g + (b.g - a.g) * t,
    a.b + (b.b - a.b) * t,
  )
}

export const VoiceOrb = {
  mounted() {
    this._state        = "idle"
    this._transcript   = ""
    this._silenceMs    = 2000
    this._silenceTimer = null
    this._animId       = null
    this._audioCtx     = null
    this._analyser     = null
    this._micStream    = null
    this._recognition  = null
    this._clock        = new THREE.Clock()

    // live voice mode state
    this._liveMode      = false
    this._captureCtx    = null
    this._captureWorklet = null

    // smoothed uniforms (start at idle values)
    this._speed    = ORB_STATES.idle.speed
    this._blobA    = ORB_STATES.idle.blobA.clone()
    this._blobB    = ORB_STATES.idle.blobB.clone()
    this._blobC    = ORB_STATES.idle.blobC.clone()
    this._rimColor = ORB_STATES.idle.rimColor.clone()

    this._buildScene()
    this._startMic()
    this._startRecognition()
    this._bindServerEvents()

    this._onTtsDone = () => {
      if (this._state === "speaking") this._setState("listening")
    }
    window.addEventListener("tts:done", this._onTtsDone)

    this._resizeObserver = new ResizeObserver(() => this._onResize())
    this._resizeObserver.observe(this.el)

    // Request live voice session — server will reply with live_voice_ready
    this.pushEvent("start_live_voice", {})
  },

  destroyed() {
    cancelAnimationFrame(this._animId)
    this._renderer?.dispose()
    this._recognition?.stop()
    this._micStream?.getTracks().forEach(t => t.stop())
    this._audioCtx?.close()
    clearTimeout(this._silenceTimer)
    window.removeEventListener("tts:done", this._onTtsDone)
    this._resizeObserver?.disconnect()
    if (this._liveMode) {
      this._stopLiveMode()
      try { this.pushEvent("stop_live_voice", {}) } catch (_) {}
    }
  },

  // ── Three.js setup ────────────────────────────────────────────────────────

  _buildScene() {
    const el   = this.el
    const size = 360

    this._scene  = new THREE.Scene()
    this._camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100)
    this._camera.position.z = 5.2

    this._renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
    this._renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    this._renderer.setSize(size, size)
    this._renderer.setClearColor(0x000000, 0)
    // round canvas so corners don't clip
    this._renderer.domElement.style.borderRadius = "50%"
    el.appendChild(this._renderer.domElement)

    this._uniforms = {
      uTime:       { value: 0 },
      uSpeed:      { value: this._speed },
      uAudioLevel: { value: 0 },
      uBlobA:      { value: this._blobA.clone() },
      uBlobB:      { value: this._blobB.clone() },
      uBlobC:      { value: this._blobC.clone() },
      uRimColor:   { value: this._rimColor.clone() },
    }

    // Smooth UV sphere — perfectly round for the liquid pearl look
    const geo = new THREE.SphereGeometry(1.95, 128, 64)
    const mat = new THREE.ShaderMaterial({
      vertexShader:   VERTEX_SHADER,
      fragmentShader: FRAGMENT_SHADER,
      uniforms:       this._uniforms,
    })

    this._mesh = new THREE.Mesh(geo, mat)
    this._scene.add(this._mesh)

    this._loop()
  },

  _loop() {
    this._animId = requestAnimationFrame(() => this._loop())

    const dt = this._clock.getDelta()
    this._uniforms.uTime.value += dt

    // Audio level from mic analyser
    let audioLevel = 0
    if (this._analyser && this._state === "listening") {
      const buf = new Uint8Array(this._analyser.frequencyBinCount)
      this._analyser.getByteFrequencyData(buf)
      const avg = buf.reduce((a, b) => a + b, 0) / buf.length
      audioLevel = Math.min(avg / 90, 1.0)
    }

    // Smooth lerp toward target state values
    const target = ORB_STATES[this._state]
    const alpha  = 1 - Math.pow(0.008, dt) // ~2s transition

    this._speed    += (target.speed    - this._speed)    * alpha
    this._blobA     = lerpColor(this._blobA,    target.blobA,    alpha)
    this._blobB     = lerpColor(this._blobB,    target.blobB,    alpha)
    this._blobC     = lerpColor(this._blobC,    target.blobC,    alpha)
    this._rimColor  = lerpColor(this._rimColor, target.rimColor, alpha)

    this._uniforms.uSpeed.value      = this._speed
    this._uniforms.uAudioLevel.value = audioLevel
    this._uniforms.uBlobA.value.copy(this._blobA)
    this._uniforms.uBlobB.value.copy(this._blobB)
    this._uniforms.uBlobC.value.copy(this._blobC)
    this._uniforms.uRimColor.value.copy(this._rimColor)

    // Very gentle rotation — keeps the orb alive without spinning
    this._mesh.rotation.y += dt * 0.06
    this._mesh.rotation.x  = Math.sin(this._uniforms.uTime.value * 0.12) * 0.08

    this._renderer.render(this._scene, this._camera)
  },

  _onResize() {
    // fixed canvas — no resize needed
  },

  // ── State machine ─────────────────────────────────────────────────────────

  _setState(state) {
    this._state = state
    const label = document.getElementById("orb-label")
    if (label) label.textContent = ORB_STATES[state]?.label ?? ""
  },

  // ── Mic + audio level ─────────────────────────────────────────────────────

  async _startMic() {
    try {
      this._micStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
      this._audioCtx  = new AudioContext()
      this._analyser  = this._audioCtx.createAnalyser()
      this._analyser.fftSize = 256
      const src = this._audioCtx.createMediaStreamSource(this._micStream)
      src.connect(this._analyser)
    } catch (_) {
      // mic access denied — orb still works without audio reactivity
    }
  },

  // ── Speech recognition ────────────────────────────────────────────────────

  _startRecognition() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SR) return

    this._recognition = new SR()
    this._recognition.continuous    = true
    this._recognition.interimResults = true
    this._recognition.lang          = "en-US"

    this._recognition.onresult = (e) => {
      if (this._state === "thinking" || this._state === "speaking") return

      let interim = ""
      for (let i = e.resultIndex; i < e.results.length; i++) {
        if (e.results[i].isFinal) {
          this._transcript += e.results[i][0].transcript + " "
        } else {
          interim += e.results[i][0].transcript
        }
      }

      const display = document.getElementById("orb-transcript")
      if (display) display.textContent = (this._transcript + interim).trim()

      if (this._state !== "listening") this._setState("listening")

      clearTimeout(this._silenceTimer)
      this._silenceTimer = setTimeout(() => this._submitTranscript(), this._silenceMs)
    }

    this._recognition.onend = () => {
      if (this._state === "idle" || this._state === "listening") {
        // auto-restart to maintain continuous listening
        setTimeout(() => { try { this._recognition.start() } catch (_) {} }, 120)
      }
    }

    this._recognition.onerror = (e) => {
      if (e.error === "no-speech" || e.error === "network") return
    }

    try { this._recognition.start() } catch (_) {}
    this._setState("listening")
  },

  _submitTranscript() {
    const text = this._transcript.trim()
    this._transcript = ""
    const display = document.getElementById("orb-transcript")
    if (display) display.textContent = ""

    if (!text) return

    this._setState("thinking")
    try { this._recognition.stop() } catch (_) {}

    this.pushEvent("voice_submit", { text })
  },

  _resumeListening() {
    this._setState("listening")
    const resp = document.getElementById("orb-response")
    if (resp) resp.textContent = ""
    if (this._liveMode) return
    try {
      this._recognition?.start()
    } catch (_) {
      setTimeout(() => { try { this._recognition?.start() } catch (_2) {} }, 300)
    }
  },

  // ── Live mode: AudioWorklet PCM16 capture ─────────────────────────────────

  async _startLiveMode() {
    this._liveMode = true
    // Null out _recognition BEFORE stopping so its onend callback can't restart it
    const rec = this._recognition
    this._recognition = null
    try { rec?.stop() } catch (_) {}

    try {
      // 16 kHz AudioContext — browser resamples getUserMedia internally
      this._captureCtx = new AudioContext({ sampleRate: 16000 })

      const stream = this._micStream || await navigator.mediaDevices.getUserMedia({ audio: true })
      const src = this._captureCtx.createMediaStreamSource(stream)

      const processorCode = `
class PCMCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this._buf = []
    this._chunkSamples = 512
  }
  process(inputs) {
    const ch = inputs[0]?.[0]
    if (!ch) return true
    for (let i = 0; i < ch.length; i++) {
      this._buf.push(ch[i])
      if (this._buf.length >= this._chunkSamples) {
        const pcm16 = new Int16Array(this._chunkSamples)
        for (let j = 0; j < this._chunkSamples; j++) {
          pcm16[j] = Math.round(Math.max(-1, Math.min(1, this._buf[j])) * 32767)
        }
        this.port.postMessage(pcm16.buffer, [pcm16.buffer])
        this._buf = this._buf.slice(this._chunkSamples)
      }
    }
    return true
  }
}
registerProcessor('pcm-capture', PCMCaptureProcessor)
`
      const blob = new Blob([processorCode], { type: 'application/javascript' })
      const blobUrl = URL.createObjectURL(blob)
      await this._captureCtx.audioWorklet.addModule(blobUrl)
      URL.revokeObjectURL(blobUrl)

      this._captureWorklet = new AudioWorkletNode(this._captureCtx, 'pcm-capture')
      src.connect(this._captureWorklet)

      this._captureWorklet.port.onmessage = (e) => {
        const bytes = new Uint8Array(e.data)
        let binary = ""
        for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
        this.pushEvent("live_audio_chunk", { data: btoa(binary) })
      }

      this._setState("listening")
    } catch (err) {
      console.error("[VoiceOrb] live mode failed, falling back to Web Speech API:", err)
      this._liveMode = false
      this._startRecognition()
    }
  },

  _stopLiveMode() {
    this._liveMode = false
    try { this._captureWorklet?.disconnect() } catch (_) {}
    this._captureWorklet = null
    try { this._captureCtx?.close() } catch (_) {}
    this._captureCtx = null
  },

  // ── Server event bindings ─────────────────────────────────────────────────

  _bindServerEvents() {
    this.handleEvent("stream_token", () => {
      if (this._state !== "thinking") this._setState("thinking")
    })

    this.handleEvent("stream_done", ({ chatterbox }) => {
      // if TTS is about to play, wait for tts:done; otherwise resume immediately
      if (chatterbox) {
        this._setState("speaking")
      } else {
        this._resumeListening()
      }
    })

    this.handleEvent("stream_cancel", () => {
      this._resumeListening()
    })

    // Live voice mode events
    this.handleEvent("live_voice_ready", async () => {
      await this._startLiveMode()
    })

    this.handleEvent("live_speech_start", () => {
      // Barge-in: user spoke while AI was responding — interrupt immediately
      if (this._state === "speaking" || this._state === "thinking") {
        this.pushEvent("live_interrupt", {})
      }
      if (this._state !== "listening") this._setState("listening")
    })

    this.handleEvent("live_processing", () => {
      // VAD fired speech_end — give immediate feedback before Whisper returns
      this._setState("thinking")
    })

    this.handleEvent("live_transcript", ({ text }) => {
      const display = document.getElementById("orb-transcript")
      if (display) display.textContent = text
      const resp = document.getElementById("orb-response")
      if (resp) resp.textContent = ""
      this._setState("thinking")
    })

    this.handleEvent("live_token", ({ token }) => {
      if (this._state !== "thinking") this._setState("thinking")
      const display = document.getElementById("orb-response")
      if (display) display.textContent += token
    })

    this.handleEvent("live_done", () => {
      // Audio chunks queued in AudioPlayer; tts:done will transition to listening
      this._setState("speaking")
      const display = document.getElementById("orb-transcript")
      if (display) display.textContent = ""
      // Keep orb-response visible while speaking; clear it when listening resumes
    })

    this.handleEvent("voice_session_lost", () => {
      this._stopLiveMode()
      // Fall back to Web Speech API so the orb stays functional
      this._startRecognition()
    })
  },
}
