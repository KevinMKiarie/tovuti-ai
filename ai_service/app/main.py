import asyncio

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes import chat, transcribe, tts, voices, actions, voice_ws

app = FastAPI(title="Tovuti AI Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:4000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat.router)
app.include_router(transcribe.router)
app.include_router(tts.router)
app.include_router(voices.router)
app.include_router(actions.router)
app.include_router(voice_ws.router)


@app.on_event("startup")
async def _prewarm():
    import logging
    log = logging.getLogger(__name__)

    async def _load():
        from fastapi.concurrency import run_in_threadpool
        try:
            from app.services import kokoro_svc
            await run_in_threadpool(kokoro_svc.get_pipeline, "a")
            await run_in_threadpool(kokoro_svc.get_pipeline, "b")
            log.info("Kokoro pipelines ready")
        except Exception as e:
            log.warning("Kokoro pre-warm skipped: %s", e)
        try:
            from app.services.vad_svc import _get_model as _get_vad_model
            await run_in_threadpool(_get_vad_model)
            log.info("Silero VAD model ready")
        except Exception as e:
            log.warning("VAD pre-warm skipped: %s", e)

    asyncio.create_task(_load())


@app.get("/health")
async def health():
    return {"status": "ok"}
