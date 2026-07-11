"""WebSocket route for real-time voice pipeline.

URL: /ws/voice

Each connection gets its own VADSession, conversation history, and generation
task. The pipeline is:

  microphone PCM16 → VAD → Whisper STT → Ollama LLM (streaming) → Kokoro TTS

Barge-in is supported: a new speech_end event cancels any in-flight generation
task before starting a fresh one.
"""

from __future__ import annotations

import asyncio
import base64
import json
import re
from typing import Optional

import httpx
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool

import os

from app.services import kokoro_svc, whisper_svc
from app.services.vad_svc import VADSession

router = APIRouter()

OLLAMA_BASE_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")

_SYSTEM_PROMPT = (
    "You are Tovuti, a helpful conversational AI assistant. "
    "Respond naturally and concisely — this is a voice conversation so keep replies brief and clear. "
    "Do not use markdown formatting, bullet points, or headers."
)

# ---------------------------------------------------------------------------
# Markdown stripping helpers
# ---------------------------------------------------------------------------

_CODE_FENCE = re.compile(r"```.*?```", re.DOTALL)
_MD_CHARS = re.compile(r"[#*_~>`|]")
_MULTI_SPACE = re.compile(r" {2,}")


def _strip_markdown(text: str) -> str:
    """Remove common markdown syntax so TTS reads clean prose."""
    text = _CODE_FENCE.sub("", text)
    text = _MD_CHARS.sub("", text)
    text = text.replace("\n", " ")
    text = _MULTI_SPACE.sub(" ", text)
    return text.strip()


def _is_complete_sentence(buf: str) -> bool:
    """True when buf contains sentence-ending punctuation and is long enough."""
    return bool(re.search(r"[.!?]", buf)) and len(buf) > 15


# ---------------------------------------------------------------------------
# Safe send helper
# ---------------------------------------------------------------------------

async def safe_send(ws: WebSocket, msg: dict) -> None:
    """Send a JSON message, silently swallowing send errors (e.g. disconnect)."""
    try:
        await ws.send_text(json.dumps(msg))
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Generation pipeline
# ---------------------------------------------------------------------------

async def generate_and_speak(
    text: str,
    websocket: WebSocket,
    conversation: list[dict],
    model: str,
    voice: str,
    pace: float,
) -> None:
    """Stream LLM tokens → TTS sentences → audio chunks concurrently.

    Parameters
    ----------
    text:
        The transcribed user utterance.
    websocket:
        Live WebSocket connection to send messages over.
    conversation:
        Mutable conversation history list (modified in place).
    model:
        Ollama model name (e.g. "phi3:mini").
    voice:
        Kokoro voice name (e.g. "af_heart").
    pace:
        TTS speed multiplier (1.0 = default natural speed).
    """
    conversation.append({"role": "user", "content": text})

    tts_queue: asyncio.Queue[Optional[str]] = asyncio.Queue()
    full_response_parts: list[str] = []

    # ------------------------------------------------------------------
    # LLM producer: stream tokens, detect sentence boundaries, enqueue.
    # ------------------------------------------------------------------

    async def llm_producer() -> None:
        messages_with_system = [{"role": "system", "content": _SYSTEM_PROMPT}] + conversation
        payload = {
            "model": model,
            "messages": messages_with_system,
            "stream": True,
            "options": {
                "num_ctx": 2048,
                "num_thread": 4,
            },
        }
        sentence_buffer = ""

        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream(
                "POST", f"{OLLAMA_BASE_URL}/api/chat", json=payload,
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    token: str = data.get("message", {}).get("content", "")
                    if token:
                        full_response_parts.append(token)
                        await safe_send(websocket, {"type": "token", "text": token})
                        sentence_buffer += token

                        if _is_complete_sentence(sentence_buffer):
                            clean = _strip_markdown(sentence_buffer)
                            if clean:
                                await tts_queue.put(clean)
                            sentence_buffer = ""

                    if data.get("done"):
                        break

        # Flush any remaining text that did not end with punctuation.
        leftover = _strip_markdown(sentence_buffer)
        if leftover:
            await tts_queue.put(leftover)

        # Sentinel to signal the consumer that production is finished.
        await tts_queue.put(None)

    # ------------------------------------------------------------------
    # TTS consumer: synthesize each sentence and send audio immediately.
    # ------------------------------------------------------------------

    final_seq: list[int] = [0]

    async def tts_consumer() -> None:
        seq = 1  # AudioPlayer.nextPlaySeq starts at 1
        while True:
            sentence = await tts_queue.get()
            if sentence is None:
                break
            try:
                wav_bytes: bytes = await run_in_threadpool(
                    kokoro_svc.synthesize, sentence, voice, pace
                )
                encoded = base64.b64encode(wav_bytes).decode()
                await safe_send(
                    websocket,
                    {"type": "audio_chunk", "seq": seq, "data": encoded},
                )
                final_seq[0] = seq
                seq += 1
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                await safe_send(websocket, {"type": "error", "message": str(exc)})

    # Run producer and consumer concurrently; cancellation propagates to both.
    await asyncio.gather(llm_producer(), tts_consumer())

    # Commit the full LLM response to conversation history.
    full_response = "".join(full_response_parts)
    if full_response:
        conversation.append({"role": "assistant", "content": full_response})

    await safe_send(websocket, {"type": "done", "final_seq": final_seq[0]})


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------

@router.websocket("/ws/voice")
async def voice_ws(websocket: WebSocket) -> None:
    await websocket.accept()

    # Initialise VAD — model download happens here on first ever connection.
    try:
        vad_session = VADSession()
    except Exception as exc:
        import logging
        logging.getLogger(__name__).error("VAD init failed: %s", exc, exc_info=True)
        await safe_send(websocket, {"type": "error", "message": f"VAD init failed: {exc}"})
        await websocket.close(code=1011)
        return

    # Per-connection state.
    conversation: list[dict] = []
    current_model: str = "phi3:mini"
    current_voice: str = "af_heart"
    current_pace: float = 1.0
    gen_task: Optional[asyncio.Task] = None

    async def _cancel_gen_task() -> None:
        """Cancel the running generation task and await its completion."""
        nonlocal gen_task
        if gen_task is not None and not gen_task.done():
            gen_task.cancel()
            try:
                await gen_task
            except (asyncio.CancelledError, Exception):
                pass
        gen_task = None

    try:
        while True:
            raw = await websocket.receive_text()

            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await safe_send(websocket, {"type": "error", "message": "invalid JSON"})
                continue

            msg_type = msg.get("type")

            # ----------------------------------------------------------------
            # ping / keepalive
            # ----------------------------------------------------------------
            if msg_type == "ping":
                await safe_send(websocket, {"type": "pong"})

            # ----------------------------------------------------------------
            # context — set conversation state
            # ----------------------------------------------------------------
            elif msg_type == "context":
                if "messages" in msg:
                    conversation = list(msg["messages"])
                if "model" in msg:
                    current_model = msg["model"]
                if "voice" in msg:
                    current_voice = msg["voice"]
                if "pace" in msg:
                    current_pace = float(msg["pace"])

            # ----------------------------------------------------------------
            # interrupt — cancel any in-flight generation
            # ----------------------------------------------------------------
            elif msg_type == "interrupt":
                await _cancel_gen_task()
                await safe_send(websocket, {"type": "interrupt_ack"})

            # ----------------------------------------------------------------
            # audio_chunk — feed into VAD
            # ----------------------------------------------------------------
            elif msg_type == "audio_chunk":
                raw_b64 = msg.get("data", "")
                try:
                    pcm16_bytes = base64.b64decode(raw_b64)
                except Exception:
                    await safe_send(
                        websocket, {"type": "error", "message": "bad base64 in audio_chunk"}
                    )
                    continue

                event = vad_session.process_chunk(pcm16_bytes)

                if event == "speech_start":
                    await safe_send(websocket, {"type": "speech_start"})
                    # Barge-in: cancel any in-progress generation.
                    if gen_task is not None and not gen_task.done():
                        await _cancel_gen_task()
                        await safe_send(websocket, {"type": "interrupt_ack"})

                elif event == "speech_end":
                    # Grab the accumulated WAV before resetting.
                    wav_bytes = vad_session.get_speech_wav()
                    vad_session.speech_chunks = []  # clear buffer immediately

                    if wav_bytes:
                        # Signal the client immediately — before Whisper runs
                        await safe_send(websocket, {"type": "processing"})
                        try:
                            transcript: str = await run_in_threadpool(
                                whisper_svc.transcribe, wav_bytes, "audio/wav"
                            )
                        except Exception as exc:
                            await safe_send(
                                websocket, {"type": "error", "message": f"STT error: {exc}"}
                            )
                            transcript = ""

                        if transcript:
                            await safe_send(websocket, {"type": "transcript", "text": transcript})

                            # Cancel any still-running generation before starting the new one.
                            await _cancel_gen_task()

                            gen_task = asyncio.create_task(
                                generate_and_speak(
                                    transcript,
                                    websocket,
                                    conversation,
                                    current_model,
                                    current_voice,
                                    current_pace,
                                )
                            )

            else:
                await safe_send(
                    websocket, {"type": "error", "message": f"unknown message type: {msg_type}"}
                )

    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await safe_send(websocket, {"type": "error", "message": str(exc)})
        except Exception:
            pass
    finally:
        # Always clean up the generation task on disconnect or error.
        if gen_task is not None and not gen_task.done():
            gen_task.cancel()
            try:
                await gen_task
            except (asyncio.CancelledError, Exception):
                pass
