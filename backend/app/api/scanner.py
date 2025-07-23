from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from ..database import get_db
from ..schemas import ScanRequest, ScanResponse
from ..scanner import VideoScanner
import os
from dotenv import load_dotenv

load_dotenv()
router = APIRouter()

@router.post("/scan", response_model=ScanResponse)
def scan_videos(
    request: ScanRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    scan_path = request.path or os.getenv("MEDIA_PATH")
    if not scan_path:
        return ScanResponse(
            status="error",
            videos_found=0,
            videos_added=0,
            errors=["No scan path provided and MEDIA_PATH not set"]
        )
    
    scanner = VideoScanner(db)
    results = scanner.scan_directory(scan_path, request.recursive)
    
    return ScanResponse(
        status="completed",
        videos_found=results['videos_found'],
        videos_added=results['videos_added'],
        errors=results['errors']
    )
