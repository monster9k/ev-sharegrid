"""Login and authenticated profile endpoints."""

from __future__ import annotations

import os
import math
from collections import OrderedDict
from threading import Lock
from time import monotonic
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from pydantic import BaseModel, Field, field_validator

from backend.auth import (
    AuthConfigurationError,
    AuthUser,
    configured_password_hashes,
    create_access_token,
    hash_password,
    DEMO_EMAILS,
    require_roles,
    verify_password,
)
from backend.db import connect, dict_cursor


class AuthRoute(APIRoute):
    """Omit submitted credentials from validation responses, including malformed bodies."""

    def get_route_handler(self):
        handler = super().get_route_handler()

        async def handle(request: Request):
            try:
                return await handler(request)
            except RequestValidationError as exc:
                errors = [
                    {key: value for key, value in error.items() if key in ("type", "loc", "msg")}
                    for error in exc.errors()
                ]
                if request.url.path.endswith("/register"):
                    messages = {
                        "email": "Địa chỉ email không hợp lệ (tối đa 100 ký tự).",
                        "password": "Mật khẩu cần từ 8 đến 128 ký tự.",
                        "full_name": "Họ tên cần từ 1 đến 100 ký tự.",
                        "phone": "Số điện thoại tối đa 20 ký tự.",
                    }
                    for error in errors:
                        error["msg"] = messages.get(error["loc"][-1], "Thông tin đăng ký không hợp lệ.")
                raise HTTPException(422, detail=errors) from None

        return handle


router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"], route_class=AuthRoute)

EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


# One fixed window shared by login and registration, per client and per process.
AUTH_LIMIT = 20
AUTH_WINDOW = 60
_buckets: OrderedDict[str, tuple[float, int]] = OrderedDict()
_bucket_lock = Lock()


def limit_auth(request: Request):
    ip = request.client.host if request.client else "unknown"
    with _bucket_lock:
        now = monotonic()
        while _buckets and next(iter(_buckets.values()))[0] <= now:
            _buckets.popitem(last=False)
        until, count = _buckets.get(ip, (now + AUTH_WINDOW, 0))
        if count >= AUTH_LIMIT or (ip not in _buckets and len(_buckets) >= 10000):
            raise HTTPException(429, detail="Quá nhiều lần thử. Vui lòng thử lại sau.",
                                headers={"Retry-After": str(math.ceil(until - now))})
        _buckets[ip] = (until, count + 1)


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=100)
    password: str = Field(default="", max_length=1024)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not EMAIL_PATTERN.fullmatch(normalized):
            raise ValueError("A valid email address is required")
        return normalized


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=8, max_length=128, repr=False)
    phone: str | None = Field(default=None, max_length=20)

    @field_validator("email", "full_name", "phone", mode="before")
    @classmethod
    def trim(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return LoginRequest.validate_email(value)


@router.post("/login", dependencies=[Depends(limit_auth)])
def login(body: LoginRequest):
    connection = None
    try:
        connection = connect()
        with dict_cursor(connection) as cursor:
            cursor.execute(
                "SELECT user_id, role, email, full_name, password_hash FROM app_user WHERE lower(email) = %s AND status = 'ACTIVE'",
                (body.email,),
            )
            row = cursor.fetchone()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Authentication user store is unavailable") from exc
    finally:
        if connection is not None:
            connection.close()

    if row is None:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    try:
        hashes = configured_password_hashes()
    except AuthConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    password_hash = hashes.get(body.email, row.get("password_hash"))
    dev_demo = body.email in hashes and os.getenv("DEV_AUTH_BYPASS", "0") == "1"
    if not dev_demo and (not password_hash or not verify_password(body.password, password_hash)):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return session_response(row)


def session_response(row):
    user = AuthUser(int(row["user_id"]), row["role"], row["email"], row["full_name"])
    try:
        access_token, expires_in = create_access_token(user)
    except AuthConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": expires_in,
        "user": {
            "user_id": user.user_id,
            "role": user.role,
            "email": user.email,
            "full_name": user.full_name,
        },
    }


@router.post("/register", dependencies=[Depends(limit_auth)])
def register(body: RegisterRequest):
    duplicate = "Email này đã được sử dụng."
    if body.email in DEMO_EMAILS:
        raise HTTPException(409, detail=duplicate)
    try:
        if body.email in configured_password_hashes():
            raise HTTPException(409, detail=duplicate)
    except AuthConfigurationError as exc:
        raise HTTPException(503, detail="Cấu hình xác thực chưa sẵn sàng.") from exc

    # Always insert normalized email. The unique constraint arbitrates concurrent inserts.
    # The lower(email) check also respects older records stored with mixed case.
    encoded = hash_password(body.password)
    connection = None
    try:
        connection = connect()
        with connection, dict_cursor(connection) as cursor:
            cursor.execute(
                """
                INSERT INTO app_user (role, full_name, email, phone, password_hash)
                SELECT 'USER', %s, %s, %s, %s
                WHERE NOT EXISTS (SELECT 1 FROM app_user WHERE lower(email) = %s)
                ON CONFLICT (email) DO NOTHING
                RETURNING user_id, role, email, full_name
                """,
                (body.full_name, body.email, body.phone, encoded, body.email),
            )
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(409, detail=duplicate)
            return session_response(row)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, detail="Chưa thể tạo tài khoản. Vui lòng thử lại sau.") from exc
    finally:
        if connection is not None:
            connection.close()


@router.get("/me")
def get_me(user: AuthUser = Depends(require_roles("USER", "HOST", "ADMIN"))):
    connection = None
    try:
        connection = connect()
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT v.vehicle_id, v.model_id, v.plate_number, v.nickname,
                       v.default_soc_target, v.is_default, vm.brand, vm.model_name,
                       vm.connector_type, vm.battery_kwh, vm.max_kw
                FROM vehicle v
                JOIN vehicle_model vm ON vm.model_id = v.model_id
                WHERE v.user_id = %s
                ORDER BY v.is_default DESC, v.vehicle_id
                """,
                (user.user_id,),
            )
            vehicles = cursor.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load account vehicles") from exc
    finally:
        if connection is not None:
            connection.close()
    return {
        "user_id": user.user_id,
        "role": user.role,
        "email": user.email,
        "full_name": user.full_name,
        "vehicles": vehicles,
    }
