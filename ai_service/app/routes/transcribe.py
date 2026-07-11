from fastapi import APIRouter, Request

from app.services import whisper_svc

router = APIRouter()


@router.post("/transcribe")
async def transcribe(request: Request):
    content_type = request.headers.get("content-type", "audio/webm")
    audio_bytes = await request.body()
    text = whisper_svc.transcribe(audio_bytes, content_type)
    return {"text": text}
