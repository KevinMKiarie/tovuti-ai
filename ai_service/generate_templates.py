"""
Generates voice template WAV files using espeak-ng at Docker build time.
Each template becomes an audio prompt that Chatterbox can clone at inference time.
"""
import io
import os
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

TEMPLATES_DIR = str(Path(__file__).resolve().parent / "voice_templates")
TARGET_SR = 24000

TEXT = (
    "Hello, I am your AI assistant. "
    "I can help you with questions, writing, coding, and much more. "
    "Let me know what you need today."
)

VOICES = [
    ("en-us-male.wav",   "en-us",    "145"),
    ("en-us-female.wav", "en-us+f3", "150"),
    ("en-gb-male.wav",   "en-gb",    "140"),
    ("en-gb-female.wav", "en-gb+f3", "148"),
    ("en-au.wav",        "en-au",    "145"),
]

os.makedirs(TEMPLATES_DIR, exist_ok=True)

for filename, voice, speed in VOICES:
    tmp = f"/tmp/{filename}"
    dest = os.path.join(TEMPLATES_DIR, filename)

    subprocess.run(
        ["espeak-ng", "-v", voice, "-s", speed, "-w", tmp, TEXT],
        check=True,
        capture_output=True,
    )

    audio, sr = sf.read(tmp)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    audio = audio.astype(np.float32)

    if sr != TARGET_SR:
        from scipy import signal
        new_len = max(1, int(len(audio) * TARGET_SR / sr))
        audio = signal.resample(audio, new_len).astype(np.float32)

    buf = io.BytesIO()
    sf.write(buf, audio, TARGET_SR, format="WAV", subtype="PCM_16")
    with open(dest, "wb") as f:
        f.write(buf.getvalue())

    print(f"Generated: {dest}")

print("Voice templates ready.")
