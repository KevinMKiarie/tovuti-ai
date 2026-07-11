# Tovuti AI

A locally-running, voice-enabled AI chat assistant. Elixir/Phoenix LiveView frontend, Python FastAPI backend, all inference runs on your machine — no cloud API keys required.

## Stack

| Layer | Technology |
|---|---|
| Web | Elixir / Phoenix LiveView |
| Database | PostgreSQL |
| LLM inference | Ollama (local) |
| Chat TTS | Kokoro-82M (fast, CPU-friendly) |
| Voice preview / cloning | Chatterbox TTS (GPU recommended) |
| Speech-to-text | faster-whisper (local) |
| AI service | Python / FastAPI (`ai_service/`) |
| Styling | Tailwind CSS |

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Elixir | ≥ 1.15 | `brew install elixir` |
| Erlang | ≥ 26 | bundled with Elixir via brew |
| Node.js | ≥ 18 | `brew install node` |
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop |
| Ollama | latest | https://ollama.com |

---

## Setup

### 1. Clone and install Elixir dependencies

```bash
mix setup
```

This runs `deps.get`, creates and migrates the database, and builds JS/CSS assets.

### 2. Start Docker services

The project uses Docker for three services: **PostgreSQL**, **Ollama**, and the **Python AI service**.

```bash
docker compose up -d
```

> **First-time build** — Docker builds the `ai_service` image which installs PyTorch, Chatterbox, Kokoro, and Whisper. This takes **5–15 minutes** depending on your connection. Subsequent starts are instant.

To check that all three services are up:

```bash
docker compose ps
```

You should see `db`, `ollama`, and `ai_service` all in `Up` state.

### 3. Pull an Ollama model

```bash
docker exec tovuti_ai-ollama-1 ollama pull phi3:mini
```

`phi3:mini` (~2.3 GB) is the default. You can change the active model in **Settings → Models** inside the app. Other good options: `llama3.2:3b`, `qwen2.5:3b`.

### 4. Start Phoenix

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

---

## Docker Services in Detail

### `db` — PostgreSQL 16

Stores conversation threads and messages. Connection config is in `config/dev.exs` (user: `postgres`, password: `postgres`, db: `tovuti_ai_dev`).

### `ollama` — Ollama LLM server

Runs the local language model on port `11434`. Models are cached in the `ollama_data` Docker volume and persist across restarts.

### `ai_service` — Python FastAPI (port 8000)

Handles TTS, STT, and chat streaming. Built from `ai_service/Dockerfile`.

**Key endpoints:**

| Endpoint | What it does |
|---|---|
| `POST /tts` | Text-to-speech. Uses **Kokoro** when `voice_id` is set (fast), **Chatterbox** when `audio_prompt_path` is set (slow, preview only). |
| `POST /transcribe` | Speech-to-text via faster-whisper. |
| `POST /chat` | Streams tokens from Ollama. |
| `GET /voices/templates` | Lists bundled voice templates. |
| `POST /voices/upload` | Saves an uploaded voice clip for cloning. |

**Volumes used by `ai_service`:**

| Volume | Mount inside container | Purpose |
|---|---|---|
| `hf_cache` | `/root/.cache/huggingface` | Caches Kokoro and Whisper model weights so they aren't re-downloaded on restart |
| `voice_clips` | `/voice_clips` | Stores uploaded voice clone WAV files |

Voice template WAV files (`priv/voice_templates/*.wav`) are baked into the image at build time via `generate_templates.py`.

---

## Rebuilding the AI Service

If you change anything in `ai_service/` (Python code, `requirements.txt`, `Dockerfile`), rebuild with:

```bash
docker compose build --no-cache ai_service
docker compose up -d ai_service
```

> Always use `--no-cache` when rebuilding. Without it, Docker may skip `COPY` layers and the container runs stale code.

To push a quick code change without a full rebuild, copy the file directly:

```bash
docker cp ai_service/app/routes/tts.py tovuti_ai-ai_service-1:/service/app/routes/tts.py
docker compose restart ai_service
```

---

## First-Run: Kokoro Model Download

On the **first request** to `/tts` with a `voice_id` (i.e. any voice template), the container downloads the Kokoro-82M model (~320 MB) from HuggingFace. This happens once and is cached in the `hf_cache` volume.

The startup pre-warm kicks this off automatically in the background when the container starts, so by the time you send your first chat message the model should already be loaded.

To watch the download progress:

```bash
docker logs -f tovuti_ai-ai_service-1
```

You'll see HuggingFace download progress, then silence once it's cached.

---

## Voice System

### Voice Templates (fast — Kokoro)

Built-in voices selectable in **Settings → Voice → Voice Templates**. Each template maps to a Kokoro voice ID:

| Template | Kokoro voice |
|---|---|
| American Male | `am_adam` |
| American Female | `af_heart` |
| British Male | `bm_george` |
| British Female | `bf_emma` |
| Australian | `am_michael` |

TTS for chat uses Kokoro: **2–5 seconds** per response on CPU.

### Voice Cloning (preview only — Chatterbox)

Chatterbox TTS is used exclusively for the **Preview** button in Settings. On CPU, Chatterbox runs ~1000 diffusion steps which takes **10–20 minutes per request** — it is not suitable for real-time chat on CPU. A GPU reduces this to seconds.

> If the AI service becomes unresponsive after clicking **Play preview**, a Chatterbox synthesis is likely blocking it. Restart the service to unblock:
> ```bash
> docker compose restart ai_service
> ```

### Uploaded Voice Clones

Uploaded clips are saved to `priv/voice_clips/` (local, not inside Docker). They are used as Chatterbox audio prompts for preview synthesis.

---

## Local Python Service (alternative to Docker)

If you prefer to run the Python service outside Docker (e.g. for faster iteration):

```bash
cd ai_service
python -m venv .venv && source .venv/bin/activate
pip install torch torchaudio --extra-index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

The service auto-resolves `VOICE_CLIPS_DIR` and `VOICE_TEMPLATES_DIR` to `../priv/voice_clips/` and `../priv/voice_templates/` relative to the repo root when running locally (no environment variable needed).

Then stop only the Docker `ai_service` and keep `db` and `ollama` running:

```bash
docker compose stop ai_service
```

---

## Environment / Configuration

All runtime config lives in `config/dev.exs`. No `.env` file needed for development.

| Key | Default | Description |
|---|---|---|
| `:ai_service_url` | `http://localhost:8000` | URL of the Python FastAPI service |
| `:ollama_url` | `http://localhost:11434` | URL of the Ollama server |
| `:ollama_model` | `phi3:mini` | Active LLM model (overridden in Settings UI) |
| `:tts_exaggeration` | `0.5` | Chatterbox expressiveness (0.25–2.0) |
| `:tts_cfg_weight` | `0.5` | Chatterbox consistency (0.0–1.0) |
| `:tts_pace` | `1.0` | Speaking speed multiplier |

Voice selection (`active_voice_path`, `active_kokoro_voice`, `active_template`, `active_voice_id`) is stored in the Erlang application environment at runtime and resets when the Phoenix server restarts.

---

## Database

```bash
# Create and migrate
mix ecto.setup

# Reset (drop + recreate + migrate)
mix ecto.reset

# Run pending migrations only
mix ecto.migrate
```

---

## Troubleshooting

**AI service not responding / templates not loading**
```bash
docker compose ps               # check all services are Up
docker logs tovuti_ai-ai_service-1 --tail 30   # check for errors
curl http://localhost:8000/health               # should return {"status":"ok"}
```

**Stuck TTS synthesis (service hangs)**
Chatterbox synthesis on CPU can run for 15+ minutes and blocks the service. Kill it:
```bash
docker compose restart ai_service
```

**Container runs stale code after `docker compose build`**
Always use `--no-cache`:
```bash
docker compose build --no-cache ai_service && docker compose up -d ai_service
```

**Database connection errors**
Make sure the `db` container is running:
```bash
docker compose up -d db
```

**Ollama model not found**
Pull the model into the running Ollama container:
```bash
docker exec tovuti_ai-ollama-1 ollama pull phi3:mini
```
