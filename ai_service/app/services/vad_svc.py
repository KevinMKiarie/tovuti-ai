"""Silero VAD session wrapper.

Each WebSocket connection should own one VADSession instance. The session
accumulates raw PCM16 audio while speech is active and exposes helpers to
retrieve it as a well-formed WAV file.
"""

from __future__ import annotations

import io
from typing import Optional

import numpy as np
import soundfile as sf
import torch

# ---------------------------------------------------------------------------
# Singleton model loader
# ---------------------------------------------------------------------------

_vad_model = None
_get_speech_timestamps = None  # kept for optional direct use


def _get_model():
    """Lazy-load the Silero VAD model exactly once per process."""
    global _vad_model, _get_speech_timestamps
    if _vad_model is None:
        from silero_vad import load_silero_vad, get_speech_timestamps as _gst
        _vad_model = load_silero_vad()
        _get_speech_timestamps = _gst
    return _vad_model


# ---------------------------------------------------------------------------
# VADSession
# ---------------------------------------------------------------------------

_SAMPLE_RATE = 16_000
_INT16_MAX = 32_768.0


class VADSession:
    """Stateful VAD session for a single WebSocket connection.

    Parameters
    ----------
    threshold:
        Probability threshold above which a frame is considered speech.
    min_silence_ms:
        Milliseconds of silence required before declaring speech ended.
    """

    def __init__(self, threshold: float = 0.5, min_silence_ms: int = 400) -> None:
        self.threshold = threshold
        self.min_silence_ms = min_silence_ms

        # Accumulated raw PCM16 bytes while speech is in progress.
        self.speech_chunks: list[bytes] = []

        self._speaking: bool = False
        self._iterator = self._make_iterator()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _make_iterator(self):
        """Build a fresh VADIterator from the (already loaded) model."""
        from silero_vad import VADIterator
        model = _get_model()
        return VADIterator(
            model,
            threshold=self.threshold,
            sampling_rate=_SAMPLE_RATE,
            min_silence_duration_ms=self.min_silence_ms,
        )

    @staticmethod
    def _pcm16_to_tensor(pcm16_bytes: bytes) -> torch.Tensor:
        """Convert raw little-endian PCM16 bytes to a float32 torch tensor."""
        samples = np.frombuffer(pcm16_bytes, dtype=np.int16).astype(np.float32)
        samples /= _INT16_MAX
        return torch.from_numpy(samples)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def process_chunk(self, pcm16_bytes: bytes) -> Optional[str]:
        """Process one 512-sample (32 ms @ 16 kHz) PCM16 chunk.

        Returns
        -------
        "speech_start"
            VAD transitioned from silence to speech on this chunk.
        "speech_end"
            VAD transitioned from speech to silence on this chunk.
            ``self.speech_chunks`` now contains the complete utterance.
        None
            No state transition (either ongoing speech or ongoing silence).
        """
        tensor = self._pcm16_to_tensor(pcm16_bytes)
        result = self._iterator(tensor, return_seconds=False)

        if result is not None:
            # Silero VADIterator returns a dict: {'start': <sample>} or
            # {'end': <sample>} to signal transitions.
            if "start" in result:
                self._speaking = True
                # Include this chunk — it contains the speech onset.
                self.speech_chunks.append(pcm16_bytes)
                return "speech_start"

            if "end" in result:
                if self._speaking:
                    # Include the final chunk before marking end.
                    self.speech_chunks.append(pcm16_bytes)
                self._speaking = False
                return "speech_end"

        # No transition; if currently speaking, keep accumulating.
        if self._speaking:
            self.speech_chunks.append(pcm16_bytes)

        return None

    def get_speech_wav(self) -> bytes:
        """Return all accumulated speech as a 16 kHz PCM16 WAV byte blob."""
        if not self.speech_chunks:
            return b""

        raw = b"".join(self.speech_chunks)
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / _INT16_MAX

        buf = io.BytesIO()
        sf.write(buf, samples, _SAMPLE_RATE, format="WAV", subtype="PCM_16")
        buf.seek(0)
        return buf.read()

    def reset(self) -> None:
        """Clear accumulated audio and reset the VADIterator internal state."""
        self.speech_chunks = []
        self._speaking = False
        self._iterator = self._make_iterator()
