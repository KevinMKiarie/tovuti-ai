import base64
import io
import json
import os
import uuid
from pathlib import Path

import numpy as np
import soundfile as sf
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

_service_root = Path(__file__).resolve().parents[2]
VOICE_CLIPS_DIR = Path(os.environ.get("VOICE_CLIPS_DIR", _service_root / "voice_clips"))
VOICE_TEMPLATES_DIR = Path(os.environ.get("VOICE_TEMPLATES_DIR", _service_root / "voice_templates"))
TARGET_SR = 24000

router = APIRouter()

VOICE_PARAMS = {
    "engine": "chatterbox",
    "parameters": {
        "exaggeration": {
            "min": 0.25,
            "max": 2.0,
            "step": 0.05,
            "default": 0.5,
            "label": "Expressiveness",
            "description": "How emotional the voice sounds. 0.25 = flat, 0.5 = natural, 1.0+ = very expressive.",
        },
        "cfg_weight": {
            "min": 0.0,
            "max": 1.0,
            "step": 0.05,
            "default": 0.5,
            "label": "Consistency",
            "description": "Lower allows natural variation in pacing; higher enforces consistent rhythm.",
        },
        "pace": {
            "min": 0.5,
            "max": 2.0,
            "step": 0.1,
            "default": 1.0,
            "label": "Pace",
            "description": "Speaking speed. 1.0 = natural, below 1.0 = slower, above 1.0 = faster.",
        },
    },
}


class VoiceUploadRequest(BaseModel):
    data: str  # base64-encoded audio bytes


@router.get("/voices")
async def list_voices():
    return VOICE_PARAMS


@router.get("/voices/templates")
async def list_voice_templates():
    meta_file = VOICE_TEMPLATES_DIR / "meta.json"
    if not meta_file.exists():
        return []
    try:
        meta = json.loads(meta_file.read_text())
    except Exception:
        return []
    result = []
    for t in meta:
        filename = t.get("filename")
        if filename:
            wav = VOICE_TEMPLATES_DIR / filename
            if not wav.exists():
                continue
            clip_path = str(wav)
        elif t.get("kokoro_voice"):
            clip_path = None
        else:
            continue
        template_id = t.get("kokoro_voice") or t.get("filename", "")
        result.append({**t, "clip_path": clip_path, "id": template_id})
    return result


@router.post("/voices/upload")
async def upload_voice_clip(request: VoiceUploadRequest):
    try:
        raw = base64.b64decode(request.data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 audio data")

    try:
        audio, sr = sf.read(io.BytesIO(raw))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode audio — upload a valid .wav or .mp3 file")

    # Convert to mono float32
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    audio = audio.astype(np.float32)

    # Resample to Chatterbox's expected rate if needed
    if sr != TARGET_SR:
        from scipy import signal as scipy_signal
        new_len = max(1, int(len(audio) * TARGET_SR / sr))
        audio = scipy_signal.resample(audio, new_len).astype(np.float32)

    VOICE_CLIPS_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid.uuid4()}.wav"
    dest = VOICE_CLIPS_DIR / filename

    buf = io.BytesIO()
    sf.write(buf, audio, TARGET_SR, format="WAV", subtype="PCM_16")
    dest.write_bytes(buf.getvalue())

    return {"clip_path": str(dest), "filename": filename}


@router.delete("/voices/{filename}")
async def delete_voice_clip(filename: str):
    # Guard against path traversal
    if "/" in filename or "\\" in filename or ".." in filename or not filename.endswith((".wav", ".mp3")):
        raise HTTPException(status_code=400, detail="Invalid filename")
    path = VOICE_CLIPS_DIR / filename
    if path.exists():
        path.unlink()
    return {"status": "ok"}
