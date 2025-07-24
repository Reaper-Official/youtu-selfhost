from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from .database import engine, Base
from .api import videos, scanner, download
import os

# Create tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="YouTube Library API", version="1.0.0")

# Configuration CORS très permissive pour résoudre les problèmes
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Permet toutes les origines
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"]
)

# Include routers
app.include_router(videos.router, prefix="/api", tags=["videos"])
app.include_router(scanner.router, prefix="/api", tags=["scanner"])
app.include_router(download.router, prefix="/api", tags=["download"])

# Serve video files
MEDIA_PATH = os.getenv("MEDIA_PATH", "/opt/youtube-videos")
if os.path.exists(MEDIA_PATH):
    app.mount("/media", StaticFiles(directory=MEDIA_PATH), name="media")

@app.get("/")
def read_root():
    return {"message": "YouTube Library API", "version": "1.0.0", "status": "running"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

# Ajouter une route pour tester CORS
@app.options("/{full_path:path}")
async def options_handler(full_path: str):
    return {"message": "OK"}