from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from app.models import ChatRequest
from app.services import ollama

router = APIRouter()


@router.post("/chat")
async def chat(request: ChatRequest):
    messages = [{"role": m.role, "content": m.content} for m in request.messages]
    return StreamingResponse(
        ollama.stream_chat(messages, model=request.model),
        media_type="application/x-ndjson",
    )
