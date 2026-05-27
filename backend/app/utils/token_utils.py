"""
QR token generation for Alpha.
Tokens are stored as plain text for Alpha.
TODO(production): hash tokens with HMAC-SHA256 before storage; compare using secrets.compare_digest.
"""
import secrets

QR_TOKEN_PREFIX = "nitksaa_evt_"
QR_TOKEN_BYTES = 32  # 256-bit entropy


def generate_qr_token() -> str:
    return QR_TOKEN_PREFIX + secrets.token_urlsafe(QR_TOKEN_BYTES)
