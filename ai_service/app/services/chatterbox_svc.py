import io

import numpy as np
import soundfile as sf

from app.services.text_prep import preprocess

_model = None


def get_model():
    global _model
    if _model is None:
        from chatterbox.tts import ChatterboxTTS
        _model = ChatterboxTTS.from_pretrained(device="cpu")
    return _model


def synthesize(
    text: str,
    exaggeration: float = 0.5,
    cfg_weight: float = 0.5,
    pace: float = 1.0,
    audio_prompt_path: str | None = None,
) -> bytes:
    model = get_model()
    wav = model.generate(
        preprocess(text),
        audio_prompt_path=audio_prompt_path,
        exaggeration=exaggeration,
        cfg_weight=cfg_weight,
    )
    audio = wav.squeeze().cpu().numpy().astype(np.float32)

    if abs(pace - 1.0) > 0.01:
        from scipy import signal
        new_len = max(1, int(len(audio) / pace))
        audio = signal.resample(audio, new_len).astype(np.float32)

    buf = io.BytesIO()
    sf.write(buf, audio, model.sr, format="WAV", subtype="PCM_16")
    buf.seek(0)
    return buf.read()
