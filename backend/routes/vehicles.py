"""Vehicles CRUD router for EV ShareGrid."""
from __future__ import annotations

from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

try:
    from backend.auth import AuthUser, require_roles
    from backend.db import connect, dict_cursor
except ModuleNotFoundError:
    from auth import AuthUser, require_roles
    from db import connect, dict_cursor

router = APIRouter(prefix="/api/v1/vehicles", tags=["Vehicles"])


class VehicleCreateSchema(BaseModel):
    model_id: int
    license_plate: Optional[str] = None
    plate_number: Optional[str] = None
    nickname: Optional[str] = None
    default_soc_target: Optional[float] = Field(default=80.0, ge=10, le=100)
    is_default: Optional[bool] = False

    @property
    def effective_plate(self) -> str:
        plate = (self.license_plate or self.plate_number or "").strip()
        if not plate:
            raise ValueError("Biển số xe không được để trống")
        return plate


class VehicleUpdateSchema(BaseModel):
    model_id: Optional[int] = None
    license_plate: Optional[str] = None
    plate_number: Optional[str] = None
    nickname: Optional[str] = None
    default_soc_target: Optional[float] = Field(default=None, ge=10, le=100)
    is_default: Optional[bool] = None

    @property
    def effective_plate(self) -> Optional[str]:
        plate = self.license_plate if self.license_plate is not None else self.plate_number
        if plate is not None:
            plate = plate.strip()
            if not plate:
                raise ValueError("Biển số xe không được để trống")
        return plate


@router.get("")
@router.get("/")
def get_user_vehicles(user: AuthUser = Depends(require_roles("USER"))):
    """Lấy danh sách xe của user kèm thông tin mẫu xe."""
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Cơ sở dữ liệu không khả dụng") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT v.vehicle_id, v.model_id, v.plate_number, v.plate_number AS license_plate,
                       v.nickname, v.default_soc_target, v.is_default,
                       vm.brand, vm.model_name, vm.vehicle_type, vm.connector_type,
                       vm.battery_kwh, vm.max_kw
                FROM vehicle v
                JOIN vehicle_model vm ON vm.model_id = v.model_id
                WHERE v.user_id = %s
                ORDER BY v.is_default DESC, v.vehicle_id ASC;
                """,
                (user.user_id,),
            )
            rows = cursor.fetchall()
            return {"status": "success", "count": len(rows), "data": rows}
    finally:
        connection.close()


@router.post("", status_code=status.HTTP_201_CREATED)
@router.post("/", status_code=status.HTTP_201_CREATED)
def create_vehicle(
    payload: VehicleCreateSchema,
    user: AuthUser = Depends(require_roles("USER")),
):
    """Đăng ký xe mới cho user."""
    try:
        plate = payload.effective_plate
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err))

    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Cơ sở dữ liệu không khả dụng") from exc

    try:
        with connection:
            with dict_cursor(connection) as cursor:
                # Kiểm tra model_id có tồn tại
                cursor.execute(
                    "SELECT model_id FROM vehicle_model WHERE model_id = %s;",
                    (payload.model_id,),
                )
                if not cursor.fetchone():
                    raise HTTPException(status_code=400, detail="Mẫu xe không tồn tại trên hệ thống")

                # Kiểm tra số lượng xe hiện có của user
                cursor.execute("SELECT COUNT(*) AS count FROM vehicle WHERE user_id = %s;", (user.user_id,))
                count_res = cursor.fetchone()
                existing_count = count_res["count"] if count_res else 0

                make_default = payload.is_default or existing_count == 0

                if make_default:
                    cursor.execute(
                        "UPDATE vehicle SET is_default = FALSE WHERE user_id = %s;",
                        (user.user_id,),
                    )

                cursor.execute(
                    """
                    INSERT INTO vehicle (user_id, model_id, plate_number, nickname, default_soc_target, is_default)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING vehicle_id, model_id, plate_number, nickname, default_soc_target, is_default;
                    """,
                    (
                        user.user_id,
                        payload.model_id,
                        plate,
                        payload.nickname or None,
                        payload.default_soc_target or 80.0,
                        make_default,
                    ),
                )
                new_vehicle = cursor.fetchone()

                # Lấy kèm thông tin model
                cursor.execute(
                    """
                    SELECT v.vehicle_id, v.model_id, v.plate_number, v.plate_number AS license_plate,
                           v.nickname, v.default_soc_target, v.is_default,
                           vm.brand, vm.model_name, vm.vehicle_type, vm.connector_type,
                           vm.battery_kwh, vm.max_kw
                    FROM vehicle v
                    JOIN vehicle_model vm ON vm.model_id = v.model_id
                    WHERE v.vehicle_id = %s;
                    """,
                    (new_vehicle["vehicle_id"],),
                )
                return {"status": "success", "data": cursor.fetchone()}
    except HTTPException:
        raise
    except Exception as exc:
        if getattr(exc, "pgcode", None) == "23505":
            raise HTTPException(
                status_code=400,
                detail=f"Biển số xe '{plate}' đã được đăng ký trên hệ thống",
            ) from exc
        raise HTTPException(status_code=500, detail="Không thể tạo xe mới") from exc
    finally:
        connection.close()


@router.patch("/{vehicle_id}")
def update_vehicle(
    vehicle_id: int,
    payload: VehicleUpdateSchema,
    user: AuthUser = Depends(require_roles("USER")),
):
    """Cập nhật thông tin xe hoặc đặt làm xe mặc định."""
    try:
        effective_plate = payload.effective_plate
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err))

    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Cơ sở dữ liệu không khả dụng") from exc

    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT vehicle_id, is_default FROM vehicle WHERE vehicle_id = %s AND user_id = %s;",
                    (vehicle_id, user.user_id),
                )
                existing = cursor.fetchone()
                if not existing:
                    raise HTTPException(status_code=404, detail="Không tìm thấy xe")

                if payload.model_id is not None:
                    cursor.execute(
                        "SELECT model_id FROM vehicle_model WHERE model_id = %s;",
                        (payload.model_id,),
                    )
                    if not cursor.fetchone():
                        raise HTTPException(status_code=400, detail="Mẫu xe không tồn tại trên hệ thống")

                if payload.is_default is True:
                    cursor.execute(
                        "UPDATE vehicle SET is_default = FALSE WHERE user_id = %s;",
                        (user.user_id,),
                    )

                updates = []
                params = []
                if payload.model_id is not None:
                    updates.append("model_id = %s")
                    params.append(payload.model_id)
                if effective_plate is not None:
                    updates.append("plate_number = %s")
                    params.append(effective_plate)
                if payload.nickname is not None:
                    updates.append("nickname = %s")
                    params.append(payload.nickname)
                if payload.default_soc_target is not None:
                    updates.append("default_soc_target = %s")
                    params.append(payload.default_soc_target)
                if payload.is_default is not None:
                    updates.append("is_default = %s")
                    params.append(payload.is_default)

                if updates:
                    params.extend([vehicle_id, user.user_id])
                    cursor.execute(
                        f"UPDATE vehicle SET {', '.join(updates)} WHERE vehicle_id = %s AND user_id = %s;",
                        params,
                    )

                cursor.execute(
                    """
                    SELECT v.vehicle_id, v.model_id, v.plate_number, v.plate_number AS license_plate,
                           v.nickname, v.default_soc_target, v.is_default,
                           vm.brand, vm.model_name, vm.vehicle_type, vm.connector_type,
                           vm.battery_kwh, vm.max_kw
                    FROM vehicle v
                    JOIN vehicle_model vm ON vm.model_id = v.model_id
                    WHERE v.vehicle_id = %s;
                    """,
                    (vehicle_id,),
                )
                return {"status": "success", "data": cursor.fetchone()}
    except HTTPException:
        raise
    except Exception as exc:
        if getattr(exc, "pgcode", None) == "23505":
            raise HTTPException(
                status_code=400,
                detail="Biển số xe đã được đăng ký trên hệ thống",
            ) from exc
        raise HTTPException(status_code=500, detail="Không thể cập nhật xe") from exc
    finally:
        connection.close()


@router.delete("/{vehicle_id}")
def delete_vehicle(
    vehicle_id: int,
    user: AuthUser = Depends(require_roles("USER")),
):
    """Xóa xe của user; chặn xóa nếu xe đang có lịch hoặc đang sạc."""
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Cơ sở dữ liệu không khả dụng") from exc

    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT vehicle_id, is_default FROM vehicle WHERE vehicle_id = %s AND user_id = %s;",
                    (vehicle_id, user.user_id),
                )
                existing = cursor.fetchone()
                if not existing:
                    raise HTTPException(status_code=404, detail="Không tìm thấy xe")

                # Kiểm tra lịch sạc đang SCHEDULED, CONFIRMED hoặc CHARGING
                cursor.execute(
                    """
                    SELECT request_id FROM charging_request
                    WHERE vehicle_id = %s AND status IN ('SCHEDULED', 'CONFIRMED', 'CHARGING')
                    LIMIT 1;
                    """,
                    (vehicle_id,),
                )
                active_req = cursor.fetchone()
                if active_req:
                    raise HTTPException(
                        status_code=400,
                        detail="Không thể xóa xe đang có lịch sạc hoặc đang sạc điện.",
                    )

                was_default = existing["is_default"]
                cursor.execute(
                    "DELETE FROM vehicle WHERE vehicle_id = %s AND user_id = %s;",
                    (vehicle_id, user.user_id),
                )

                # Nếu xe bị xóa là mặc định, chuyển mặc định sang xe còn lại (nếu có)
                if was_default:
                    cursor.execute(
                        """
                        UPDATE vehicle SET is_default = TRUE
                        WHERE vehicle_id = (
                            SELECT vehicle_id FROM vehicle
                            WHERE user_id = %s
                            ORDER BY vehicle_id ASC
                            LIMIT 1
                        );
                        """,
                        (user.user_id,),
                    )

                return {
                    "status": "success",
                    "message": "Đã xóa xe thành công",
                }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Không thể xóa xe") from exc
    finally:
        connection.close()
