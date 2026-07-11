#!/usr/bin/env bash
# Run from the repo root: bash commit.bash
set -e

MSG=/tmp/_tovuti_commit_msg.txt

commit() {
  git commit -F "$MSG"
  rm -f "$MSG"
}

# ─── Guard: keep .env out of git ──────────────────────────────────────────
grep -qxF '.env' .gitignore || echo '.env' >> .gitignore
git add .gitignore


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 1 — Dev environment, Docker Compose, product spec
# ══════════════════════════════════════════════════════════════════════════════
git add config/dev.exs docker-compose.yml SPEC.md

cat > "$MSG" <<'MSG'
chore: configure dev environment, Docker Compose, and product spec

Sets up the full local development stack and documents the product vision.

config/dev.exs
- Registers :ai_service_url (http://localhost:8000) and :ollama_url
  (http://localhost:11434) so every part of the app resolves these
  through Application.get_env rather than hard-coding strings.
- Seeds default TTS parameter values: exaggeration 0.5, cfg_weight 0.5,
  pace 1.0. These are runtime-mutable via Application.put_env from
  SettingsLive so they survive LiveView restarts within a session.
- Sets the default Ollama model to phi3:mini (fast, fits in ~4 GB RAM).

docker-compose.yml -- three services, all on localhost:
- db: postgres:16-alpine on 5432; credentials match dev.exs; persists
  data in a named pgdata volume so the database survives container
  restarts.
- ollama: official ollama/ollama image on 11434; stores downloaded models
  in an ollama_data volume so they are not re-pulled on every restart.
- ai_service: built from ./ai_service; maps 8000:8000; mounts hf_cache
  (Hugging Face model weights) and voice_clips (user-uploaded reference
  audio) as named volumes so they persist across container rebuilds.
  Depends on ollama so Ollama is reachable when the service starts.

SPEC.md -- full product specification for Tovuti AI:
- Phase 1: voice-enabled local AI chat (Ollama LLM, Whisper STT,
  Chatterbox TTS) with a clean conversational UI.
- Phase 2: Perplexity-style answer panels with source citations,
  follow-up chips, and a collapsible thread sidebar.
- Phase 3: full conversation persistence -- threads, message history,
  and thread management.

No cloud dependencies -- every service runs on the machine.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 2 — Database migrations
# ══════════════════════════════════════════════════════════════════════════════
git add \
  priv/repo/migrations/20260627100000_create_threads.exs \
  priv/repo/migrations/20260627100001_create_messages.exs \
  priv/repo/migrations/20260628120000_create_voice_clones.exs

cat > "$MSG" <<'MSG'
feat: add database migrations for conversations and voice clones

Three Ecto migrations, all using binary_id (UUID v4) primary keys to
avoid leaking record counts and to make IDs safe for public URLs.

20260627100000_create_threads
- Stores one row per conversation session.
- Fields: id (uuid PK), title (text), inserted_at / updated_at (UTC).

20260627100001_create_messages
- Stores individual chat turns within a thread.
- Fields: id (uuid PK), thread_id (uuid FK -> threads, on_delete:
  delete_all so messages are cleaned up when a thread is deleted),
  role (string not null, "user" or "assistant"), content (text not null),
  audio_path (text nullable, reserved for caching TTS audio on disk),
  timestamps. Indexed on thread_id for efficient per-thread queries.

20260628120000_create_voice_clones
- Stores user-uploaded voice reference clips for Chatterbox voice cloning.
- Fields: id (uuid PK), name (string not null, display label), clip_path
  (string not null, absolute path to the processed 24 kHz mono WAV
  written by the AI service), timestamps.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 3 — Conversations context (Thread + Message)
# ══════════════════════════════════════════════════════════════════════════════
git add \
  lib/tovuti_ai/conversations.ex \
  lib/tovuti_ai/conversations/

cat > "$MSG" <<'MSG'
feat: add Conversations context with Thread and Message schemas

Persistence layer for all chat history.

lib/tovuti_ai/conversations/thread.ex
- Ecto schema; binary_id PK; title field; has_many :messages.
- Changeset validates presence of title.

lib/tovuti_ai/conversations/message.ex
- Ecto schema; binary_id PK; role, content, audio_path fields;
  belongs_to :thread (binary_id FK).
- Changeset validates role is one of ["user", "assistant"] and requires
  role, content, and thread_id.

lib/tovuti_ai/conversations.ex -- public API:
- list_threads/0: all threads ordered by inserted_at desc (sidebar).
- get_thread_with_messages/1: fetches a thread and preloads its messages
  ordered by inserted_at asc for chronological display.
- create_thread/1: inserts a new thread row.
- create_message/1: inserts a single message under an existing thread.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 4 — VoiceClones context
# ══════════════════════════════════════════════════════════════════════════════
git add \
  lib/tovuti_ai/voice_clones.ex \
  lib/tovuti_ai/voice_clones/

cat > "$MSG" <<'MSG'
feat: add VoiceClones context with VoiceClone schema

Manages user-uploaded voice reference clips used by Chatterbox TTS
for zero-shot voice cloning.

lib/tovuti_ai/voice_clones/voice_clone.ex
- Ecto schema; binary_id PK; name (required, 1-100 chars), clip_path
  (required, absolute path to the processed WAV on disk).
- clip_path is always written by the AI service after normalisation,
  never taken raw from user input.

lib/tovuti_ai/voice_clones.ex -- public API:
- list_voices/0: all clones ordered by inserted_at asc (upload order).
- get_voice!/1: fetch by UUID; used before deletion to retrieve clip_path.
- create_voice/1: insert after a successful AI service upload.
- delete_voice/1: remove the row; caller handles filesystem cleanup.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 5 — Python AI service
# ══════════════════════════════════════════════════════════════════════════════
git add ai_service/

cat > "$MSG" <<'MSG'
feat: add Python AI service for Whisper STT, Chatterbox TTS, and Ollama proxy

FastAPI application (port 8000) bridging the Phoenix app to local AI models.
All heavy models are lazy-loaded on first request to keep startup time near zero.

Routes
------

POST /chat
  Proxies a messages array and model name to Ollama /api/chat and returns
  a StreamingResponse of newline-delimited JSON for incremental consumption.

POST /transcribe
  Accepts raw audio bytes (webm or wav) via request body. Writes a temp
  file, runs faster-whisper base.en (English-only, int8-quantised, CPU),
  and returns {"text": "..."}.

POST /tts
  Accepts text and TTS params (exaggeration, cfg_weight, pace) plus an
  optional audio_prompt_path for voice cloning. Calls ChatterboxTTS,
  applies scipy.signal.resample when pace != 1.0, and returns base64
  PCM WAV at 24 kHz.

GET /voices
  Returns the Chatterbox parameter schema (min/max/step/default/label/
  description) so the Settings UI can render sliders without hard-coding
  ranges in Elixir.

POST /voices/upload
  Accepts base64 audio, converts to mono float32, resamples to 24 kHz,
  saves to /voice_clips/<uuid>.wav, and returns the clip_path.

DELETE /voices/{filename}
  Removes a clip; includes a path-traversal guard rejecting filenames
  containing slashes, "..", or extensions other than .wav/.mp3.

Services
--------

whisper_svc.py     -- faster-whisper base.en, CPU, int8 quantisation.
chatterbox_svc.py  -- ChatterboxTTS.from_pretrained on CPU; scipy resample
                      for pace != 1.0; returns 24 kHz PCM_16 WAV bytes.
ollama.py          -- async httpx streaming proxy (ctx 2048, threads 4).
text_prep.py       -- TTS text normaliser: collapses repeated punctuation,
                      expands ALL-CAPS to Title Case, replaces ellipsis
                      with em-dash, auto-inserts commas before coordinating
                      conjunctions, folds newlines.

Infrastructure
--------------

Dockerfile: python:3.11-slim + ffmpeg + espeak-ng + CPU-only PyTorch;
runs uvicorn on 0.0.0.0:8000.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 6 — Router
# ══════════════════════════════════════════════════════════════════════════════
git add lib/tovuti_ai_web/router.ex

cat > "$MSG" <<'MSG'
feat: add LiveView routes for chat and settings

  GET /              -> ChatLive :index   (fresh chat)
  GET /t/:thread_id  -> ChatLive :show    (resume saved conversation)
  GET /settings      -> SettingsLive :index

The /t/:thread_id segment lets ChatLive load a thread by UUID on mount,
enabling bookmarkable conversation URLs. The URL is pushed into browser
history after the first message is sent so it works without a page reload.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 7 — ChatLive
# ══════════════════════════════════════════════════════════════════════════════
git add lib/tovuti_ai_web/live/chat_live.ex

cat > "$MSG" <<'MSG'
feat: add ChatLive -- real-time streaming chat with voice I/O

Primary LiveView for the entire user-facing chat experience.

Conversation flow
-----------------

submit event:
1. Creates a Thread (title = first 80 chars of the user message) and
   persists the user turn as a Message.
2. Pushes /t/:thread_id into the browser URL so the conversation is
   bookmarkable from the first message.
3. Spawns a Task that POSTs to Ollama /api/chat with stream: true via Req.
   The into: callback uses the req 0.6.x {req, resp} accumulator pattern;
   each NDJSON chunk sends {:ai_token, token} to the LiveView process.
4. Tokens are appended to current_response for live display.
5. On :ai_stream_done the full response is saved as an assistant Message,
   then a Task requests Chatterbox synthesis from /tts; the base64 WAV is
   pushed to the AudioPlayer JS hook via push_event("play_audio", ...).

Voice input
-----------

transcription_result event: receives the transcript from MicRecorder,
places it in the input field, and immediately triggers submit -- completing
the voice-in / voice-out loop with no typing required.

Thread loading
--------------

handle_params (:show action): calls Conversations.get_thread_with_messages/1
and assigns the loaded messages so full history renders on page load.

new_chat event: resets all transient state and navigates to / without a
full page reload.

State
-----

Assigns: messages, current_response, streaming, recording, sidebar_open,
thread_id. The LiveView process itself is the state machine.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 8 — SettingsLive
# ══════════════════════════════════════════════════════════════════════════════
git add lib/tovuti_ai_web/live/settings_live.ex

cat > "$MSG" <<'MSG'
feat: add SettingsLive -- model management, TTS tuning, and voice clones

Two-tab settings page at /settings.

Models tab
----------

Lists 8 curated Ollama models (Phi-3 Mini, Qwen 2.5 3B/7B, Llama 3.2
1B/3B, Mistral 7B, Gemma 2 2B, DeepSeek R1 7B) with size and description.

On mount queries Ollama /api/tags to build an installed set; each card
shows an "Installed" badge without a separate per-model request.
select_model persists the choice via Application.put_env so it is picked
up immediately by the next ChatLive stream.

pull_model spawns a Task that streams download progress from Ollama
/api/pull using the req 0.6.x {req, resp} accumulator pattern. Progress
is rendered as a percentage bar; on success the model list refreshes.

Voice tab
---------

Upload (allow_upload :voice_clip, .wav/.mp3, max 50 MB):
  consume_uploaded_entries reads the temp file, base64-encodes it, and
  POSTs to /voices/upload. On success the clip_path is saved via
  VoiceClones.create_voice/1 and the voice appears in the list immediately.

Preview: POSTs current preview_text and active TTS params to /tts and pushes
the base64 WAV to AudioPlayer so the user can audition before selecting.

Delete: removes the Postgres row via VoiceClones.delete_voice/1, then fires
a background Task to DELETE /voices/:filename on the AI service.

select_voice / use_default_voice: persist the active clip_path via
Application.put_env so every subsequent /tts call picks it up.

TTS parameters
--------------

Sliders for exaggeration (0.25-2.0), cfg_weight (0.0-1.0), and pace
(0.5-2.0) update via update_tts_param events and persist with
Application.put_env.
MSG
commit


# ══════════════════════════════════════════════════════════════════════════════
# COMMIT 9 — JavaScript hooks
# ══════════════════════════════════════════════════════════════════════════════
git add assets/js/hooks.js assets/js/app.js

cat > "$MSG" <<'MSG'
feat: add AudioPlayer and MicRecorder LiveView hooks

AudioPlayer
-----------

Attached to the chat container. Manages two audio paths:

Streaming TTS (incremental, low-latency):
  Listens for stream_token push events as Ollama tokens arrive. Buffers
  tokens, detects sentence boundaries (. ! ? ...), and enqueues each
  sentence to the browser SpeechSynthesis API so speech begins while the
  LLM is still generating.

Pre-rendered TTS (Chatterbox, high quality):
  Listens for play_audio push events carrying a base64 WAV. Decodes via
  AudioContext.decodeAudioData and plays through a BufferSourceNode for
  accurate pause, resume, and replay control.

Playback bar: Pause/Resume and Replay buttons; tracks playing/paused/idle
state. stream_done and stream_cancel flush the speech queue cleanly.

MicRecorder
-----------

Attached to the mic button. Toggles Web Speech Recognition on click
(continuous: false, interimResults: false, lang: en-US). On result
fires transcription_result to the LiveView with the recognised text.
ChatLive auto-submits it, completing the voice-in / voice-out loop with
no typing required. Updates button aria-pressed and a CSS recording class
for visual feedback during capture.

app.js
------

Registers AudioPlayer and MicRecorder with the LiveSocket alongside the
topbar NProgress integration.
MSG
commit


echo ""
echo "All 9 commits created."
echo "Review with:  git log --oneline"
echo "Push with:    git push origin main"
