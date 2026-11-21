"""Authentication helpers for signed, short-lived backend access tokens."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass
from typing import Any

from fastapi import Depends, HTTPException, Request

from backend.db import connect, dict_cursor


DEMO_EMAILS = ("user1@sharegrid.vn", "host1@sharegrid.vn", "admin@sharegrid.vn")
ISSUER = "ev-sharegrid"
PBKDF2_ITERATIONS = 310_000


@dataclass(frozen=True)
class AuthUser:
    user_id: int
    role: str
    email: str
    full_name: str


class AuthConfigurationError(RuntimeError):
    """Required authentication secrets or password hashes are unavailable."""


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _jwt_secret() -> bytes:
    secret = os.getenv("JWT_SECRET", "").encode("utf-8")
    if len(secret) < 32:
        raise AuthConfigurationError("JWT_SECRET must contain at least 32 bytes")
    return secret


def token_lifetime_seconds() -> int:
    try:
        minutes = int(os.getenv("JWT_TTL_MINUTES", "60"))
    except ValueError as exc:
        raise AuthConfigurationError("JWT_TTL_MINUTES must be an integer") from exc
    if not 1 <= minutes <= 1440:
        raise AuthConfigurationError("JWT_TTL_MINUTES must be between 1 and 1440")
    return minutes * 60


def create_access_token(user: AuthUser, *, now: int | None = None) -> tuple[str, int]:
    issued_at = int(time.time()) if now is None else int(now)
    expires_at = issued_at + token_lifetime_seconds()
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "iss": ISSUER,
        "sub": str(user.user_id),
        "role": user.role,
        "iat": issued_at,
        "exp": expires_at,
    }
    signing_input = f"{_b64encode(json.dumps(header, separators=(',', ':')).encode())}.{_b64encode(json.dumps(payload, separators=(',', ':')).encode())}"
    signature = hmac.new(_jwt_secret(), signing_input.encode("ascii"), hashlib.sha256).digest()
    return f"{signing_input}.{_b64encode(signature)}", expires_at - issued_at


def decode_access_token(token: str, *, now: int | None = None) -> dict[str, Any]:
    try:
        encoded_header, encoded_payload, encoded_signature = token.split(".")
        signing_input = f"{encoded_header}.{encoded_payload}"
        expected = hmac.new(_jwt_secret(), signing_input.encode("ascii"), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64decode(encoded_signature)):
            raise ValueError("bad signature")
        header = json.loads(_b64decode(encoded_header))
        claims = json.loads(_b64decode(encoded_payload))
        current_time = int(time.time()) if now is None else int(now)
        if header != {"alg": "HS256", "typ": "JWT"}:
            raise ValueError("unsupported token header")
        if claims.get("iss") != ISSUER or int(claims["exp"]) <= current_time:
            raise ValueError("expired or invalid token")
        if int(claims["iat"]) > current_time or claims.get("role") not in {"USER", "HOST", "ADMIN"}:
            raise ValueError("invalid token claims")
        claims["sub"] = int(claims["sub"])
        return claims
    except AuthConfigurationError:
        raise
    except Exception as exc:
        raise ValueError("invalid or expired access token") from exc


def hash_password(password: str, *, salt: bytes | None = None) -> str:
    """Create the server-configured PBKDF2 format used in AUTH_PASSWORD_HASHES_JSON."""
    salt_value = secrets.token_bytes(16) if salt is None else salt
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt_value, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt_value.hex()}${digest.hex()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, raw_iterations, salt_hex, digest_hex = encoded.split("$", 3)
        iterations = int(raw_iterations)
        if algorithm != "pbkdf2_sha256" or not 100_000 <= iterations <= 2_000_000:
            return False
        expected = bytes.fromhex(digest_hex)
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt_hex), iterations)
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def configured_password_hashes() -> dict[str, str]:
    raw = os.getenv("AUTH_PASSWORD_HASHES_JSON", "").strip()
    if not raw:
        raise AuthConfigurationError("AUTH_PASSWORD_HASHES_JSON is not configured")
    try:
        values = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AuthConfigurationError("AUTH_PASSWORD_HASHES_JSON must be a JSON object") from exc
    if not isinstance(values, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in values.items()):
        raise AuthConfigurationError("AUTH_PASSWORD_HASHES_JSON must map email addresses to password hashes")
    return {email.strip().lower(): password_hash for email, password_hash in values.items()}


def _fetch_active_user_by_id(user_id: int) -> AuthUser | None:
    connection = connect()
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                "SELECT user_id, role, email, full_name FROM app_user WHERE user_id = %s AND status = 'ACTIVE'",
                (user_id,),
            )
            row = cursor.fetchone()
            return AuthUser(int(row["user_id"]), row["role"], row["email"], row["full_name"]) if row else None
    finally:
        connection.close()


def get_current_user(request: Request) -> AuthUser:
    """Authenticate by signed token; the dev bypass is an explicit local-only setting."""
    if os.getenv("DEV_AUTH_BYPASS", "0") == "1":
        try:
            user_id = int(os.getenv("DEV_AUTH_USER_ID", "3"))
        except ValueError as exc:
            raise HTTPException(status_code=503, detail="DEV_AUTH_USER_ID must be an integer") from exc
        try:
            user = _fetch_active_user_by_id(user_id)
        except Exception as exc:
            raise HTTPException(status_code=503, detail="Authentication user store is unavailable") from exc
        if user is None:
            raise HTTPException(status_code=401, detail="Development user is not active")
        return user

    authorization = request.headers.get("Authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Bearer access token is required")
    try:
        claims = decode_access_token(token)
    except AuthConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc
    try:
        user = _fetch_active_user_by_id(claims["sub"])
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Authentication user store is unavailable") from exc
    if user is None or user.role != claims["role"]:
        raise HTTPException(status_code=401, detail="Account is inactive or token role is no longer valid")
    return user


def require_roles(*roles: str):
    allowed = frozenset(roles)

    def dependency(user: AuthUser = Depends(get_current_user)) -> AuthUser:
        if user.role not in allowed:
            raise HTTPException(status_code=403, detail="This account is not allowed to perform this action")
        return user

    return dependency
