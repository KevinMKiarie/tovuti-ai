from pydantic import BaseModel
from typing import Literal


class Message(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    model: str = "llama3"


class TTSRequest(BaseModel):
    text: str
    exaggeration: float = 0.5
    cfg_weight: float = 0.5
    pace: float = 1.0
    audio_prompt_path: str | None = None
    voice_id: str | None = None  # Kokoro voice id; takes priority over audio_prompt_path for chat