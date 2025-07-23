from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from ..database import get_db
from ..models import Video as VideoModel
from ..schemas import Video, VideoUpdate
from datetime import datetime

router = APIRouter()

@router.get("/videos", response_model=List[Video])
def get_videos(
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    channel: Optional[str] = None,
    watched: Optional[bool] = None,
    db: Session = Depends(get_db)
):
    query = db.query(VideoModel)
    
    if search:
        query = query.filter(
            VideoModel.title.contains(search) | 
            VideoModel.description.contains(search)
        )
    
    if channel:
        query = query.filter(VideoModel.channel_name == channel)
    
    if watched is not None:
        query = query.filter(VideoModel.watched == watched)
    
    videos = query.offset(skip).limit(limit).all()
    return videos

@router.get("/videos/{video_id}", response_model=Video)
def get_video(video_id: str, db: Session = Depends(get_db)):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    return video

@router.patch("/videos/{video_id}")
def update_video(
    video_id: str,
    video_update: VideoUpdate,
    db: Session = Depends(get_db)
):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    
    if video_update.watched is not None:
        video.watched = video_update.watched
    
    if video_update.last_watched is not None:
        video.last_watched = video_update.last_watched
        video.local_views += 1
    
    db.commit()
    db.refresh(video)
    return video

@router.delete("/videos/{video_id}")
def delete_video(video_id: str, db: Session = Depends(get_db)):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    
    db.delete(video)
    db.commit()
    return {"message": "Video deleted"}

@router.get("/channels")
def get_channels(db: Session = Depends(get_db)):
    channels = db.query(VideoModel.channel_name).distinct().all()
    return [{"name": channel[0]} for channel in channels if channel[0]]
