import httpx
import json
from typing import AsyncIterator

OLLAMA_BASE_URL = "http://localhost:11434"


async def stream_chat(messages: list[dict], model: str = "llama3") -> AsyncIterator[str]:
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "options": {
            "num_ctx": 2048,
            "num_thread": 4,
        },
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", f"{OLLAMA_BASE_URL}/api/chat", json=payload) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    token = data.get("message", {}).get("content", "")
                    if token:
                        yield json.dumps({"token": token}) + "\n"
                    if data.get("done"):
                        yield json.dumps({"done": True}) + "\n"
                except json.JSONDecodeError:
                    continue
