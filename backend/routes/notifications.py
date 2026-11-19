"""User-scoped notification inbox."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from backend.auth import AuthUser, require_roles
from backend.db import connect, dict_cursor


router = APIRouter(prefix="/api/v1/notifications", tags=["Notifications"])
ALL_ROLES = require_roles("USER", "HOST", "ADMIN")


@router.get("")
def list_notifications(
    limit: int = Query(default=50, ge=1, le=200),
    user: AuthUser = Depends(ALL_ROLES),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Notification database is unavailable") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT notif_id, request_id, type, title, body, channel,
                       created_at, sent_at, read_at
                FROM notification
                WHERE user_id = %s
                ORDER BY created_at DESC, notif_id DESC
                LIMIT %s
                """,
                (user.user_id, limit),
            )
            rows = cursor.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load notifications") from exc
    finally:
        connection.close()
    return {"count": len(rows), "notifications": rows}


@router.patch("/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    user: AuthUser = Depends(ALL_ROLES),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Notification database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    """
                    UPDATE notification
                    SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
                    WHERE notif_id = %s AND user_id = %s
                    RETURNING notif_id, read_at
                    """,
                    (notification_id, user.user_id),
                )
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(status_code=404, detail="Notification not found")
                result = {"notification_id": int(row["notif_id"]), "read_at": row["read_at"]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not mark notification as read") from exc
    finally:
        connection.close()
    return result
