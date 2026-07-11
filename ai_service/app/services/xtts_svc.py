import io

import numpy as np
import soundfile as sf

from app.services.text_prep import preprocess

_tts = None
_available = None

SAMPLE_RATE = 24000


def is_available() -> bool:
    global _available
    if _available is None:
        try:
            import TTS  # noqa: F401
            _available = True
        except ImportError:
            _available = False
    return _available


def get_model():
    global _tts
    if _tts is None:
        from TTS.api import TTS
        _tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)
    return _tts


def synthesize(text: str, audio_prompt_path: str, language: str = "en") -> bytes:
    model = get_model()
    wav = model.tts(text=preprocess(text), speaker_wav=audio_prompt_path, language=language)
    audio = np.array(wav, dtype=np.float32)
    buf = io.BytesIO()
    sf.write(buf, audio, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    buf.seek(0)
    return buf.read()
