import os
import httpx

_API_KEY = os.environ.get("CALCOM_API_KEY", "")
_BASE = "https://api.cal.com/v1"


def _key() -> str:
    if not _API_KEY:
        raise ValueError("Cal.com API key not set. Add it in Settings → Connectors.")
    return _API_KEY


def get_upcoming_bookings() -> list:
    with httpx.Client(timeout=10.0) as client:
        resp = client.get(f"{_BASE}/bookings", params={"apiKey": _key(), "status": "upcoming"})
        resp.raise_for_status()
        return resp.json().get("bookings", [])


def reschedule_booking(booking_ref: str, new_start_time: str, reason: str = "") -> dict:
    with httpx.Client(timeout=15.0) as client:
        if booking_ref:
            resp = client.get(f"{_BASE}/bookings/{booking_ref}", params={"apiKey": _key()})
            if resp.status_code == 404:
                raise ValueError(f"Booking '{booking_ref}' not found.")
            booking = resp.json().get("booking", resp.json())
        else:
            bookings = get_upcoming_bookings()
            if not bookings:
                raise ValueError("No upcoming bookings found.")
            booking = bookings[0]

        booking_id = booking.get("id")
        resp = client.post(
            f"{_BASE}/bookings/{booking_id}/reschedule",
            params={"apiKey": _key()},
            json={
                "start": new_start_time,
                "rescheduledReason": reason or "Rescheduled via Tovuti AI",
            },
        )
        resp.raise_for_status()
        return resp.json()
