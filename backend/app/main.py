from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from .database import engine, Base
from .api import videos, scanner
import os

# Create tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="YouTube Library API")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(videos.router, prefix="/api", tags=["videos"])
app.include_router(scanner.router, prefix="/api", tags=["scanner"])

# Serve video files
if os.getenv("MEDIA_PATH"):
    app.mount("/media", StaticFiles(directory=os.getenv("MEDIA_PATH")), name="media")

@app.get("/")
def read_root():
    return {"message": "YouTube Library API", "version": "1.0.0"}
