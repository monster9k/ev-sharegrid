import os
import sys
from pathlib import Path

# Thêm thư mục gốc để giữ import package ổn định khi chạy uvicorn từ repo root.
BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent
if str(PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECT_DIR))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from backend.routes.auth import router as auth_router
from backend.routes.admin import router as admin_router
from backend.routes.host import router as host_router
from backend.routes.notifications import router as notifications_router
from backend.routes.request_actions import router as request_actions_router
from backend.routes.requests import router as requests_router

app = FastAPI(title="EV ShareGrid Backend API", version="1.0.0")

cors_origins = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS", "https://ev-sharegrid.web.app,https://ev-sharegrid.firebaseapp.com"
    ).split(",")
    if origin.strip()
]
if "*" in cors_origins:
    raise ValueError("CORS_ORIGINS must list explicit origins when credentials are enabled")

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=os.getenv(
        "CORS_ORIGIN_REGEX", r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
    ) or None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(requests_router)
app.include_router(request_actions_router)
app.include_router(auth_router)
app.include_router(host_router)
app.include_router(admin_router)
app.include_router(notifications_router)

@app.get("/")
def root():
    return {"message": "EV ShareGrid API Server đang hoạt động!"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
