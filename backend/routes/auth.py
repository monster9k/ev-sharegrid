"""Login and authenticated profile endpoints."""

from __future__ import annotations

import os
import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from backend.auth import (
    AuthConfigurationError,
    AuthUser,
    configured_password_hashes,
    create_access_token,
    require_roles,
    verify_password,
)
from backend.db import connect, dict_cursor


router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


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


@router.post("/login")
def login(body: LoginRequest):
    connection = None
    try:
        connection = connect()
        with dict_cursor(connection) as cursor:
            cursor.execute(
                "SELECT user_id, role, email, full_name FROM app_user WHERE lower(email) = %s AND status = 'ACTIVE'",
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
    if os.getenv("DEV_AUTH_BYPASS", "0") != "1":
        try:
            password_hash = configured_password_hashes().get(body.email)
        except AuthConfigurationError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        if password_hash is None or not verify_password(body.password, password_hash):
            raise HTTPException(status_code=401, detail="Invalid email or password")

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
