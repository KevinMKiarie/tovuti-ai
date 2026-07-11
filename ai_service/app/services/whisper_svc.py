from faster_whisper import WhisperModel
import tempfile
import os

_model = None


def get_model():
    global _model
    if _model is None:
        _model = WhisperModel("base.en", device="cpu", compute_type="int8")
    return _model


def transcribe(audio_bytes: bytes, content_type: str = "audio/webm") -> str:
    ext = ".webm" if "webm" in content_type else ".wav"
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as f:
        f.write(audio_bytes)
        tmp_path = f.name
    try:
        segments, _ = get_model().transcribe(tmp_path)
        return " ".join(seg.text for seg in segments).strip()
    finally:
        os.unlink(tmp_path)
