from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from ..database import get_db
from ..schemas import DownloadRequest, DownloadResponse, DownloadProgress
from ..downloader import VideoDownloader
import os
from dotenv import load_dotenv

load_dotenv()
router = APIRouter()

# Initialize downloader with media path
MEDIA_PATH = os.getenv("MEDIA_PATH", "/opt/youtube-videos")
downloader = VideoDownloader(MEDIA_PATH)

@router.post("/download", response_model=DownloadResponse)
async def download_video(
    request: DownloadRequest,
    db: Session = Depends(get_db)
):
    """Start downloading a YouTube video"""
    try:
        # Validate URL
        if not request.url.startswith(('https://www.youtube.com/', 'https://youtube.com/', 'https://youtu.be/')):
            raise HTTPException(status_code=400, detail="Invalid YouTube URL")
        
        # Start download
        task_id = await downloader.download_video(
            request.url, 
            request.quality,
            db
        )
        
        return DownloadResponse(
            task_id=task_id,
            message="Download started successfully"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/download/{task_id}", response_model=DownloadProgress)
def get_download_status(task_id: str):
    """Get status of a download task"""
    status = downloader.get_download_status(task_id)
    if not status:
        raise HTTPException(status_code=404, detail="Download task not found")
    
    return DownloadProgress(**status)

@router.get("/downloads", response_model=List[DownloadProgress])
def get_all_downloads():
    """Get all active downloads"""
    downloads = downloader.get_all_downloads()
    return [DownloadProgress(**status) for status in downloads.values()]

@router.delete("/download/{task_id}")
def cancel_download(task_id: str):
    """Cancel a download task"""
    if not downloader.cancel_download(task_id):
        raise HTTPException(status_code=404, detail="Download task not found")
    
    return {"message": "Download cancelled"}

@router.post("/download/metadata")
async def get_video_metadata(request: DownloadRequest):
    """Get video metadata without downloading"""
    try:
        import yt_dlp
        
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
            'skip_download': True
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(request.url, download=False)
            
            # Get available formats
            formats = []
            if 'formats' in info:
                seen_resolutions = set()
                for f in info['formats']:
                    if f.get('height'):
                        resolution = f"{f['height']}p"
                        if resolution not in seen_resolutions and f.get('vcodec') != 'none':
                            seen_resolutions.add(resolution)
                            formats.append({
                                'format_id': f['format_id'],
                                'resolution': resolution,
                                'ext': f.get('ext', 'mp4'),
                                'filesize': f.get('filesize', 0)
                            })
                
                # Sort by resolution
                formats.sort(key=lambda x: int(x['resolution'][:-1]), reverse=True)
            
            return {
                'title': info.get('title'),
                'duration': info.get('duration'),
                'thumbnail': info.get('thumbnail'),
                'uploader': info.get('uploader'),
                'view_count': info.get('view_count'),
                'formats': formats[:5]  # Return top 5 quality options
            }
            
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error fetching metadata: {str(e)}")