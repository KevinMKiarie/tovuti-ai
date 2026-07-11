import os
import base64
from email.mime.text import MIMEText

_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
_CREDS_PATH = os.environ.get("GMAIL_CREDENTIALS_PATH", "/app_data/gmail_credentials.json")
_TOKEN_PATH = os.environ.get("GMAIL_TOKEN_PATH", "/app_data/gmail_token.json")

# Held in memory between /auth_url and /callback
_pending_flow = None


def is_connected() -> bool:
    if not os.path.exists(_TOKEN_PATH):
        return False
    try:
        from google.oauth2.credentials import Credentials
        creds = Credentials.from_authorized_user_file(_TOKEN_PATH, _SCOPES)
        return creds.valid or bool(creds.expired and creds.refresh_token)
    except Exception:
        return False


def get_auth_url() -> str:
    global _pending_flow
    from google_auth_oauthlib.flow import Flow
    if not os.path.exists(_CREDS_PATH):
        raise FileNotFoundError(
            "gmail_credentials.json not found. Download OAuth 2.0 credentials from "
            "Google Cloud Console and save to priv/action_config/gmail_credentials.json"
        )
    _pending_flow = Flow.from_client_secrets_file(
        _CREDS_PATH,
        scopes=_SCOPES,
        redirect_uri="http://localhost:8000/actions/gmail/callback",
    )
    auth_url, _ = _pending_flow.authorization_url(prompt="consent", access_type="offline")
    return auth_url


def handle_callback(code: str) -> None:
    global _pending_flow
    if _pending_flow is None:
        raise ValueError("No pending OAuth flow. Visit /actions/gmail/auth_url first.")
    _pending_flow.fetch_token(code=code)
    creds = _pending_flow.credentials
    os.makedirs(os.path.dirname(_TOKEN_PATH), exist_ok=True)
    with open(_TOKEN_PATH, "w") as f:
        f.write(creds.to_json())
    _pending_flow = None


def _get_creds():
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    if not os.path.exists(_TOKEN_PATH):
        raise ValueError("Gmail not connected. Please connect in Settings → Connectors.")
    creds = Credentials.from_authorized_user_file(_TOKEN_PATH, _SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(_TOKEN_PATH, "w") as f:
            f.write(creds.to_json())
    if not creds.valid:
        raise ValueError("Gmail token invalid. Please reconnect in Settings → Connectors.")
    return creds


def send_email(to: str, subject: str, body: str) -> dict:
    from googleapiclient.discovery import build
    creds = _get_creds()
    service = build("gmail", "v1", credentials=creds)
    msg = MIMEText(body)
    msg["to"] = to
    msg["subject"] = subject
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    result = service.users().messages().send(userId="me", body={"raw": raw}).execute()
    return {"message_id": result["id"], "status": "sent", "to": to, "subject": subject}
