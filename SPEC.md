# Tovuti AI — Product Specification

A locally-running, voice-enabled AI search chatbot modelled after Perplexity AI.
The Elixir/Phoenix frontend (LiveView) talks to a Python `ai_service` over HTTP.
All inference runs locally via Ollama; no cloud AI API keys required.

---

## Stack

| Layer | Technology |
|---|---|
| Web framework | Elixir / Phoenix LiveView |
| Database | PostgreSQL (via Ecto) |
| AI inference | Ollama (local LLM) |
| Text-to-Speech | Kokoro-82M (local, open-source) |
| Speech-to-Text | OpenAI Whisper (local, open-source) |
| AI service runtime | Python (FastAPI in `ai_service/`) |
| Styling | Tailwind CSS + DaisyUI |

---

## Phases

### Phase 1 — Voice + AI Core

Goal: get a working voice loop before touching the UI.

**1.1 — Ollama integration (Python)**

- Spin up an Ollama instance (e.g. `llama3`, `mistral`, or `phi3`).
- Python service exposes `POST /chat` that streams tokens from Ollama back to Phoenix over Server-Sent Events or WebSocket.
- Phoenix LiveView forwards the streamed response to the browser in real time.

**1.2 — TTS with Kokoro AI**

- Add `kokoro` Python package to `ai_service`.
- After the LLM response is complete, synthesise it with Kokoro and stream the resulting audio as a WAV/PCM blob.
- Phoenix receives the audio bytes and pushes them to the browser via a LiveView binary push; the browser plays them with the Web Audio API.
- Voice selection: default to `af_heart` (Kokoro's high-quality English voice).

**1.3 — STT with OpenAI Whisper (local)**

- Add `openai-whisper` Python package to `ai_service`.
- Expose `POST /transcribe` that accepts a raw audio blob (recorded in the browser via `MediaRecorder`) and returns the transcription JSON.
- Phoenix sends the recorded blob to the Python service and, on success, populates the chat input field with the transcription, then auto-submits.
- Default model: `base.en` (fast, English-only, ~140 MB). Swap to `small` or `medium` for accuracy.

**Phase 1 deliverable:** user presses a mic button → speaks → Whisper transcribes → Ollama answers → Kokoro reads the answer aloud.

---

### Phase 2 — Perplexity-Style UI

Goal: make the app look and feel like Perplexity AI.

**Layout reference**

```
┌─────────────────────────────────────────────────┐
│  [Logo]          Tovuti AI          [History]   │
├────────────┬────────────────────────────────────┤
│            │                                    │
│  Sidebar   │   Answer panel (streaming text)    │
│  (threads) │                                    │
│            │   Sources / citations block        │
│            │                                    │
│            │   Follow-up chips                  │
│            ├────────────────────────────────────┤
│            │  [🎤] Ask anything...   [⏎ Search] │
└────────────┴────────────────────────────────────┘
```

**UI components to build**

| Component | Notes |
|---|---|
| Home / zero-state | Centred logo + large input, suggested prompts |
| Search input bar | Rounded pill, mic icon left, submit right; identical to Perplexity |
| Answer card | Streams tokens in real time; Markdown rendered |
| Sources strip | Horizontal scrollable cards (domain favicon + title + snippet) |
| Follow-up chips | 3–4 auto-generated follow-up question buttons |
| Sidebar | Thread list, new-chat button, collapse toggle |
| TTS playback bar | Mini audio bar that appears beneath the answer |
| Dark / light theme | Perplexity uses a dark-teal palette; replicate it |

**Colour tokens (Perplexity-inspired)**

```css
--bg-base:       #0f1117;
--bg-surface:    #1a1d27;
--bg-elevated:   #22263a;
--accent:        #20c0a0;   /* teal */
--text-primary:  #e8eaf0;
--text-secondary:#8b90a0;
--border:        #2a2e42;
```

---

### Phase 3 — Conversation Storage

Goal: persist threads so users can resume any past conversation.

**Data model**

```
threads
  id          uuid PK
  title       text          -- first user message, truncated
  inserted_at timestamp

messages
  id          uuid PK
  thread_id   uuid FK → threads.id
  role        text          -- "user" | "assistant"
  content     text
  audio_path  text nullable -- path to cached TTS audio file
  inserted_at timestamp
```

**Behaviour**

- A new `Thread` is created on the first message of a session.
- Thread title = first 60 characters of the first user message.
- Every user prompt and assistant response is saved as a `Message`.
- The sidebar lists threads ordered by most recently active.
- Clicking a thread restores the full message history into the chat panel.
- Threads can be renamed or deleted from the sidebar context menu.
- TTS audio is cached per message (`priv/static/audio/<message_id>.wav`) so replaying is instant.

---

## Python AI Service (`ai_service/`)

```
ai_service/
  app/
    main.py          # FastAPI entry point
    routes/
      chat.py        # POST /chat   → streams Ollama tokens
      transcribe.py  # POST /transcribe → Whisper STT
      tts.py         # POST /tts    → Kokoro synthesis
    services/
      ollama.py      # Ollama HTTP client wrapper
      whisper.py     # Whisper model loader + transcription
      kokoro.py      # Kokoro pipeline wrapper
    models.py        # Pydantic request/response schemas
  requirements.txt
  Dockerfile
```

Phoenix communicates with the service via `Req` (already in `mix.exs`). The service URL is configured in `config/dev.exs` as `config :tovuti_ai, :ai_service_url, "http://localhost:8000"`.

---

## Development Startup

```bash
# Terminal 1 — Ollama
ollama serve
ollama pull llama3

# Terminal 2 — Python AI service
cd ai_service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# Terminal 3 — Phoenix
mix phx.server
```

Or use the provided `docker-compose.yml` to run all services together.

---

## Open Questions / Decisions to Make

- **STT language**: Whisper `base.en` vs. multilingual `base` (Whisper multilingual adds ~30 MB but supports Swahili — relevant given the product name *Tovuti*).
- **Streaming protocol**: SSE vs. Phoenix Channels for token streaming.
- **Audio caching policy**: evict old TTS files after N days or keep indefinitely.
- **Ollama model default**: `llama3:8b` gives a good quality/speed tradeoff on Apple Silicon; consider `phi3:mini` for speed on CPU-only machines.
- **Search grounding**: Phase 1 uses the LLM's parametric knowledge only. A future phase could add a local web-search tool (e.g. SearXNG) to give Perplexity-style source citations from live results.
