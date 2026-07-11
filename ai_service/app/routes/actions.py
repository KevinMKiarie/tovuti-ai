from typing import Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from app.services import gmail_svc, calcom_svc, whatsapp_svc

router = APIRouter(prefix="/actions", tags=["actions"])


# ── Request models ──────────────────────────────────────────────────────────

class SendEmailRequest(BaseModel):
    to: str
    subject: str
    body: str


class RescheduleMeetingRequest(BaseModel):
    booking_ref: str = ""
    new_start_time: str
    reason: str = ""


class SendWhatsAppRequest(BaseModel):
    phone: str  # single number or comma-separated list
    message: str


# ── Gmail ───────────────────────────────────────────────────────────────────

@router.get("/gmail/status")
async def gmail_status():
    return {"connected": gmail_svc.is_connected()}


@router.get("/gmail/auth_url")
async def gmail_auth_url():
    try:
        url = gmail_svc.get_auth_url()
        return {"url": url}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/gmail/callback")
async def gmail_callback(code: Optional[str] = None, error: Optional[str] = None):
    if error:
        return HTMLResponse(
            f"<html><body><h2>Gmail authorization denied</h2>"
            f"<p>{error}</p>"
            f"<p>You can close this tab and try again from Tovuti settings.</p></body></html>"
        )
    if not code:
        return HTMLResponse(
            "<html><body><h2>Invalid callback</h2>"
            "<p>No authorization code received. Please try connecting Gmail again from Tovuti settings.</p>"
            "</body></html>",
            status_code=400,
        )
    try:
        gmail_svc.handle_callback(code)
        return HTMLResponse(
            "<html><body><h2>Gmail connected!</h2>"
            "<p>You can close this tab and return to Tovuti.</p></body></html>"
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/send_email")
async def send_email(req: SendEmailRequest):
    try:
        return gmail_svc.send_email(req.to, req.subject, req.body)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Gmail error: {exc}")


# ── Cal.com ─────────────────────────────────────────────────────────────────

@router.get("/calcom/upcoming")
async def calcom_upcoming():
    try:
        bookings = calcom_svc.get_upcoming_bookings()
        return {"bookings": bookings}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Cal.com error: {exc}")


@router.post("/reschedule_meeting")
async def reschedule_meeting(req: RescheduleMeetingRequest):
    try:
        return calcom_svc.reschedule_booking(req.booking_ref, req.new_start_time, req.reason)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Cal.com error: {exc}")


# ── WhatsApp ─────────────────────────────────────────────────────────────────

@router.get("/whatsapp/status")
async def whatsapp_status():
    return whatsapp_svc.get_status()


@router.get("/whatsapp/qr")
async def whatsapp_qr():
    try:
        return whatsapp_svc.get_qr_code()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/send_whatsapp")
async def send_whatsapp(req: SendWhatsAppRequest):
    try:
        return whatsapp_svc.send_message(req.phone, req.message)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"WhatsApp error: {exc}")


@router.get("/whatsapp/connection")
async def whatsapp_connection():
    """Lightweight status check for polling after QR scan."""
    return whatsapp_svc.get_status()
