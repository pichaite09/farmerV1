"""Firebase Cloud Messaging integration; credentials are read only from env."""
from app.database import settings

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:  # pragma: no cover - optional until FCM is configured
    firebase_admin = None
    credentials = messaging = None


def _app():
    if firebase_admin is None:
        raise RuntimeError('Firebase Admin dependency is not installed')
    if firebase_admin._apps:
        return firebase_admin.get_app()
    required = (settings.firebase_project_id, settings.firebase_client_email, settings.firebase_private_key)
    if not all(required):
        raise RuntimeError('Firebase Admin is not configured')
    private_key = settings.firebase_private_key
    return firebase_admin.initialize_app(credentials.Certificate({
        'type': 'service_account', 'project_id': settings.firebase_project_id,
        'client_email': settings.firebase_client_email, 'private_key': private_key.replace('\\n', '\n'),
        'token_uri': 'https://oauth2.googleapis.com/token',
    }))


def send_fcm(token: str, payload: dict) -> str:
    return messaging.send(messaging.Message(
        token=token,
        notification=messaging.Notification(title=payload['title'], body=payload['body']),
        data={str(k): str(v) for k, v in payload.items()}, app=_app(),
    ))
