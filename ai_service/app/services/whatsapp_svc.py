import os
import httpx

_URL = os.environ.get("EVOLUTION_API_URL", "http://localhost:8080")
_KEY = os.environ.get("EVOLUTION_API_KEY", "tovuti_evo_key_change_me")
_INSTANCE = os.environ.get("EVOLUTION_INSTANCE", "tovuti")


def _headers() -> dict:
    return {"apikey": _KEY, "Content-Type": "application/json"}


def _normalize(phone: str) -> str:
    return phone.replace("+", "").replace(" ", "").replace("-", "")


def get_status() -> dict:
    try:
        with httpx.Client(timeout=5.0) as client:
            resp = client.get(f"{_URL}/instance/fetchInstances", headers=_headers())
            if resp.status_code != 200:
                return {"connected": False, "state": "error"}
            for inst in resp.json():
                # Evolution API v2 returns fields directly; v1 nested under "instance"
                name = inst.get("name") or inst.get("instance", {}).get("instanceName")
                if name == _INSTANCE:
                    state = inst.get("connectionStatus") or inst.get("instance", {}).get("connectionStatus", "unknown")
                    return {"connected": state == "open", "state": state}
            return {"connected": False, "state": "not_created"}
    except Exception as exc:
        return {"connected": False, "state": f"unreachable: {exc}"}


def get_qr_code() -> dict:
    with httpx.Client(timeout=15.0) as client:
        # Create instance if it doesn't exist yet
        client.post(
            f"{_URL}/instance/create",
            headers=_headers(),
            json={"instanceName": _INSTANCE, "qrcode": True, "integration": "WHATSAPP-BAILEYS"},
        )
        resp = client.get(f"{_URL}/instance/connect/{_INSTANCE}", headers=_headers())
        resp.raise_for_status()
        data = resp.json()
        return {"qr_base64": data.get("base64", ""), "code": data.get("code", "")}


def send_message(phones: str, message: str) -> dict:
    """Send message to one or more recipients.

    phones: single number or comma-separated list, e.g. "+254712345678,+254798765432"
    """
    status = get_status()
    if not status["connected"]:
        raise ValueError(
            f"WhatsApp not connected (state: {status['state']}). "
            "Scan the QR code in Settings → Connectors."
        )

    numbers = [_normalize(p.strip()) for p in phones.split(",") if p.strip()]
    results = []

    with httpx.Client(timeout=20.0) as client:
        for number in numbers:
            resp = client.post(
                f"{_URL}/message/sendText/{_INSTANCE}",
                headers=_headers(),
                json={"number": number, "text": message},
            )
            resp.raise_for_status()
            results.append({
                "phone": number,
                "message_id": resp.json().get("key", {}).get("id", ""),
            })

    return {
        "status": "sent",
        "recipients": results,
        "count": len(results),
    }
