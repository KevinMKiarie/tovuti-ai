import base64

from fastapi import APIRouter
from fastapi.concurrency import run_in_threadpool

from app.models import TTSRequest
from app.services import chatterbox_svc, kokoro_svc, xtts_svc

router = APIRouter()

MAX_TTS_CHARS = 600


@router.post("/tts")
async def text_to_speech(request: TTSRequest):
    text = request.text[:MAX_TTS_CHARS]

    if request.voice_id:
        # Kokoro: fast CPU inference, used for voice templates
        audio_bytes = await run_in_threadpool(
            kokoro_svc.synthesize,
            text,
            voice=request.voice_id,
            speed=request.pace,
        )
    elif request.audio_prompt_path:
        if xtts_svc.is_available():
            # XTTS v2: high-quality voice cloning from an audio prompt
            audio_bytes = await run_in_threadpool(
                xtts_svc.synthesize,
                text,
                audio_prompt_path=request.audio_prompt_path,
            )
        else:
            # Chatterbox fallback when coqui-tts is not installed
            audio_bytes = await run_in_threadpool(
                chatterbox_svc.synthesize,
                text,
                exaggeration=request.exaggeration,
                cfg_weight=request.cfg_weight,
                pace=request.pace,
                audio_prompt_path=request.audio_prompt_path,
            )
    else:
        # Chatterbox: built-in default voice, no cloning
        audio_bytes = await run_in_threadpool(
            chatterbox_svc.synthesize,
            text,
            exaggeration=request.exaggeration,
            cfg_weight=request.cfg_weight,
            pace=request.pace,
        )

    return {"audio": base64.b64encode(audio_bytes).decode()}
