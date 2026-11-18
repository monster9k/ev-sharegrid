"""Owner-checked lifecycle actions for charging requests."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from backend.ai_contract import AIUpstreamError, trigger_cluster_reoptimize
from backend.auth import AuthUser, require_roles
from backend.db import connect, dict_cursor


router = APIRouter(prefix="/api/v1/requests", tags=["Request Lifecycle"])


def _row_value(row, key: str, index: int):
    return row[key] if isinstance(row, Mapping) else row[index]


def _not_found():
    raise HTTPException(status_code=404, detail="Charging request not found")


@router.post("/{request_id}/confirm")
def confirm_request(
    request_id: int,
    user: AuthUser = Depends(require_roles("USER")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Request database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT status FROM charging_request WHERE request_id = %s AND user_id = %s FOR UPDATE",
                    (request_id, user.user_id),
                )
                row = cursor.fetchone()
                if row is None:
                    _not_found()
                status = _row_value(row, "status", 0)
                if status not in {"SCHEDULED", "CONFIRMED"}:
                    raise HTTPException(status_code=409, detail=f"Request cannot be confirmed from status {status}")
                cursor.execute(
                    "UPDATE charging_request SET status = 'CONFIRMED' WHERE request_id = %s AND user_id = %s",
                    (request_id, user.user_id),
                )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not confirm charging request") from exc
    finally:
        connection.close()
    return {"request_id": request_id, "status": "CONFIRMED"}


@router.post("/{request_id}/cancel")
def cancel_request(
    request_id: int,
    user: AuthUser = Depends(require_roles("USER")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Request database is unavailable") from exc
    cluster_id = None
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT cluster_id, status FROM charging_request WHERE request_id = %s AND user_id = %s FOR UPDATE",
                    (request_id, user.user_id),
                )
                row = cursor.fetchone()
                if row is None:
                    _not_found()
                cluster_id = int(_row_value(row, "cluster_id", 0))
                status = _row_value(row, "status", 1)
                if status not in {"PENDING", "SCHEDULED", "CONFIRMED"}:
                    raise HTTPException(status_code=409, detail=f"Request cannot be cancelled from status {status}")
                cursor.execute(
                    "UPDATE charging_request SET status = 'CANCELLED' WHERE request_id = %s AND user_id = %s",
                    (request_id, user.user_id),
                )
                cursor.execute(
                    "UPDATE schedule SET is_active = FALSE WHERE request_id = %s AND is_active = TRUE AND slot_start >= CURRENT_TIMESTAMP",
                    (request_id,),
                )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not cancel charging request") from exc
    finally:
        connection.close()

    try:
        result = trigger_cluster_reoptimize(cluster_id, trigger_type="USER_CANCEL")
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return {"request_id": request_id, "status": "CANCELLED", "optimization_status": result.status.value}


@router.post("/{request_id}/checkin")
def checkin_request(
    request_id: int,
    user: AuthUser = Depends(require_roles("USER")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Request database is unavailable") from exc
    session_id = None
    cluster_id = None
    is_late = False
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    """
                    SELECT cluster_id, status, arrival_time, departure_time, soc_now,
                           CURRENT_TIMESTAMP AS checked_at
                    FROM charging_request
                    WHERE request_id = %s AND user_id = %s
                    FOR UPDATE
                    """,
                    (request_id, user.user_id),
                )
                row = cursor.fetchone()
                if row is None:
                    _not_found()
                cluster_id = int(_row_value(row, "cluster_id", 0))
                status = _row_value(row, "status", 1)
                arrival_time = _row_value(row, "arrival_time", 2)
                departure_time = _row_value(row, "departure_time", 3)
                soc_now = _row_value(row, "soc_now", 4)
                checked_at = _row_value(row, "checked_at", 5)
                if status not in {"SCHEDULED", "CONFIRMED"}:
                    raise HTTPException(status_code=409, detail=f"Request cannot check in from status {status}")
                if checked_at < arrival_time:
                    raise HTTPException(status_code=409, detail="Check-in is only allowed at or after arrival_time")
                if checked_at >= departure_time:
                    raise HTTPException(status_code=409, detail="The request departure time has passed")

                cursor.execute(
                    "SELECT session_id FROM charging_session WHERE request_id = %s AND status = 'IN_PROGRESS' AND end_time IS NULL FOR UPDATE",
                    (request_id,),
                )
                if cursor.fetchone() is not None:
                    raise HTTPException(status_code=409, detail="An active charging session already exists")
                cursor.execute(
                    """
                    SELECT port_id FROM schedule
                    WHERE request_id = %s AND is_active = TRUE
                      AND slot_start + INTERVAL '15 minutes' > CURRENT_TIMESTAMP
                    ORDER BY slot_start LIMIT 1
                    FOR UPDATE
                    """,
                    (request_id,),
                )
                schedule = cursor.fetchone()
                if schedule is None:
                    raise HTTPException(status_code=409, detail="No active charging slot is available for check-in")
                port_id = int(_row_value(schedule, "port_id", 0))
                cursor.execute(
                    """
                    INSERT INTO charging_session (request_id, port_id, start_time, soc_start, status, is_simulated)
                    VALUES (%s, %s, CURRENT_TIMESTAMP, %s, 'IN_PROGRESS', FALSE)
                    RETURNING session_id
                    """,
                    (request_id, port_id, soc_now),
                )
                session = cursor.fetchone()
                session_id = int(_row_value(session, "session_id", 0))
                cursor.execute(
                    "UPDATE charging_request SET status = 'CHARGING' WHERE request_id = %s AND user_id = %s",
                    (request_id, user.user_id),
                )
                is_late = checked_at > arrival_time
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not check in charging request") from exc
    finally:
        connection.close()

    response = {"request_id": request_id, "session_id": session_id, "port_id": port_id, "status": "CHARGING"}
    if is_late:
        try:
            result = trigger_cluster_reoptimize(cluster_id, trigger_type="LATE_CHECKIN")
        except AIUpstreamError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
        response["optimization_status"] = result.status.value
    return response
