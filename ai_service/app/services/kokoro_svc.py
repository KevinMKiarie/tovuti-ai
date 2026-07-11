import io
import numpy as np
import soundfile as sf

from app.services.text_prep import preprocess

_pipelines: dict[str, object] = {}

# Voices that carry natural prosody well sound better at a slightly relaxed
# pace; 1.0 feels rushed on Kokoro because the model's default tempo is fast.
_NATURAL_SPEED: dict[str, float] = {
    "af_heart":    0.95,
    "af_bella":    0.93,
    "af_nicole":   0.95,
    "af_sky":      0.97,
    "am_adam":     0.92,
    "am_michael":  0.93,
    "am_fenrir":   0.91,
    "am_liam":     0.94,
    "am_echo":     0.92,
    "am_eric":     0.93,
    "bf_emma":     0.94,
    "bf_isabella": 0.93,
    "bm_george":   0.92,
    "bm_lewis":    0.93,
}

# Voice name prefix → Kokoro lang_code
_LANG_CODES: dict[str, str] = {
    "af": "a",  # American Female
    "am": "a",  # American Male
    "bf": "b",  # British Female
    "bm": "b",  # British Male
}


def _lang_code_for(voice: str) -> str:
    return _LANG_CODES.get(voice[:2], "a")


def get_pipeline(lang_code: str = "a"):
    if lang_code not in _pipelines:
        from kokoro import KPipeline
        _pipelines[lang_code] = KPipeline(lang_code=lang_code)
    return _pipelines[lang_code]


def synthesize(text: str, voice: str = "af_heart", speed: float = 1.0) -> bytes:
    # Apply natural speed default only when the caller hasn't overridden speed.
    if speed == 1.0:
        speed = _NATURAL_SPEED.get(voice, 0.94)

    pipeline = get_pipeline(_lang_code_for(voice))
    chunks = []
    for _, _, audio in pipeline(preprocess(text), voice=voice, speed=speed):
        chunks.append(audio)

    combined = np.concatenate(chunks) if chunks else np.zeros(0, dtype=np.float32)

    buf = io.BytesIO()
    sf.write(buf, combined, 24000, format="WAV", subtype="PCM_16")
    buf.seek(0)
    return buf.read()
