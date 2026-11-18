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
from backend.routes.requests import router as requests_router

app = FastAPI(title="EV ShareGrid Backend API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://ev-sharegrid.web.app"],
    allow_origin_regex=r"^http://localhost(?::\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(requests_router)

@app.get("/")
def root():
    return {"message": "EV ShareGrid API Server đang hoạt động!"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
